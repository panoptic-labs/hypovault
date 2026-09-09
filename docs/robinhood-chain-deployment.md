# Robinhood Chain deterministic architecture deployment

This runbook prepares two independent production deployments:

1. the five-contract `HypoVault` architecture; and
2. the governance `TimelockController`.

Neither workflow creates vault instances. The timelock workflow also does not transfer
ownership; ownership handoff belongs in a separate, later reviewed transaction batch.

## Network and deployment inputs

| Input                    | Value                                                                |
| ------------------------ | -------------------------------------------------------------------- |
| Chain ID                 | `4663`                                                               |
| RPC alias                | `robinhood`                                                          |
| Explorer                 | `https://robinhoodchain.blockscout.com`                              |
| CREATE2 deployer         | `0x4e59b44847b379578588920cA78FbF26c0B4956C`                         |
| Broadcast sender         | `0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8`                         |
| Salt                     | `0xe78b3302c1a713353b49c40fcbd176c072797bfcd948b809b61bf8fd3216ea8b` |
| HypoVault implementation | `0xF16714665955DBd0361D997eFc50fe391D96E8D0`                         |
| HypoVaultFactory         | `0xd5049B2647de57141dE7F65E5124707B99A452A3`                         |
| Robinhood WETH           | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`                         |
| PanopticVaultAccountant  | `0x9e345d862c41010F87D8E5A279e8D320D2831D36`                         |
| Decoder                  | `0xC87c45d2dbE5acb56013e2591427ECC84Fa251E6`                         |
| RolesAuthority           | `0xb952D345c413Ddb7850173422bAe4968e0330598`                         |

The production architecture salt is the literal value of
`keccak256(bytes("my-salt-v1"))`. The literal hash is retained as the source of truth so
an accidental label change cannot alter the deployment addresses.

The accountant constructor is `(BROADCASTER, WETH)`. The decoder constructor references
the deterministic `HypoVault` implementation. The RolesAuthority constructor is
`(BROADCASTER, address(0))`, where the zero address is its optional parent authority.
The accountant and RolesAuthority remain owned by the broadcaster until the separate
timelock handoff. The decoder is not ownable.

## Timelock inputs

| Input                   | Value                                                                |
| ----------------------- | -------------------------------------------------------------------- |
| TimelockController      | `0xaeB1ad4d0452fd79eD7dDE25A08Fd60346c60912`                         |
| Salt label              | `hypovault-timelock-v1`                                              |
| Salt                    | `0x5894bdfe5513cb18dd7f6e5ae30cd1bbcf26773ae48d25d0d72c472384825707` |
| Init code hash          | `0xe2b9422b27a33697d9c1f32e55fd0e96817d67f969ec8214b9646a2717d33e7e` |
| Minimum delay           | `1 day` (`86400` seconds)                                            |
| Proposer/Canceller Safe | `0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1`                         |
| Expected Safe threshold | `3`                                                                  |
| Executor                | `address(0)` (open execution)                                        |
| Admin                   | `address(0)` (self-administered)                                     |

These are the exact constructor inputs, CREATE2 salt, compiler settings, and dependency
bytecode used for the Ethereum production timelock, so they reproduce the Ethereum
address on Robinhood Chain.

Configure the Alchemy endpoint without committing its API key:

```sh
export ROBINHOOD_ALCHEMY_API_KEY='<key>'
```

## Approved signer setup

`--sender` only selects the address Foundry uses when constructing and simulating
transactions. It does not provide signing credentials. A broadcast must also use an
approved signer that resolves to the configured broadcaster
`0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8`.

Before adding `--broadcast`, configure one of the team's approved signing paths outside
the repository:

- the Turnkey signing workflow for the configured broadcaster;
- a Foundry keystore selected with `--account <approved-account>`; or
- an approved hardware or remote signer with its corresponding Foundry signer options.

Verify the resolved signer address before broadcasting. Do not place a raw private key
in this repository, the command line, shell history, or the runbook. The final command
must use the same `--sender` shown below together with the chosen signer-specific options.

## Architecture pre-broadcast procedure

1. Confirm the sender has at least `0.01 ETH` on Robinhood Chain.
2. Run the deterministic deployment tests:

   ```sh
   forge test --match-contract RobinhoodDeterministicDeploymentTest -vv
   ```

3. Run a simulation and inspect all five predicted addresses:

   ```sh
   forge script script/DeployHypoVaultArchitectureRobinhood.s.sol \
     --rpc-url robinhood \
     --sender 0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8 \
     -vvvv
   ```

4. On the first attempt, recheck that the canonical deployer and Robinhood WETH have code
   and all five target addresses are empty. On a recovery attempt, the script accepts an
   existing target only when its runtime code and configured state match exactly.
5. Obtain explicit approval before adding `--broadcast`.

For broadcast, use `--slow` so each transaction is confirmed in order: implementation,
factory, accountant, decoder, then RolesAuthority. Do not add `--broadcast` during
preparation or review. These are separate transactions, not one atomic transaction. If a
later transaction fails after earlier receipts succeed, rerun the same script: it validates
and skips correct existing deployments and sends only the missing transactions. It aborts
before sending new transactions if existing code or state is unexpected.

After all five receipts are successful, run the read-only live verification:

```sh
forge script script/VerifyHypoVaultArchitectureRobinhood.s.sol \
  --rpc-url robinhood \
  -vv
```

## Timelock pre-broadcast procedure

1. Run the same deterministic deployment test suite shown above.
2. Run a simulation and inspect the predicted address and constructor inputs:

   ```sh
   forge script script/DeployTimelockControllerRobinhood.s.sol \
     --rpc-url robinhood \
     --sender 0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8 \
     -vvvv
   ```

3. Confirm the simulation checks all of the following:
   - the chain ID is `4663`;
   - the canonical CREATE2 deployer has the expected runtime code hash;
   - the timelock target address is empty;
   - the proposer Safe has code and a threshold of `3`; and
   - the predicted address equals `0xaeB1ad4d0452fd79eD7dDE25A08Fd60346c60912`.
4. Obtain explicit approval before adding `--broadcast`.

After the receipt is successful, run the read-only live verification:

```sh
forge script script/VerifyTimelockControllerRobinhood.s.sol \
  --rpc-url robinhood \
  -vv
```

The verifier checks the delay, proposer and canceller roles, open executor role,
self-admin role, and absence of an admin role for the broadcaster. Do not combine this
deployment with ownership transfers.

## Deployment record

Status: **Not broadcast**

| Contract                 | Transaction hash | Block number | Gas used |
| ------------------------ | ---------------- | ------------ | -------- |
| HypoVault implementation | Pending          | Pending      | Pending  |
| HypoVaultFactory         | Pending          | Pending      | Pending  |
| PanopticVaultAccountant  | Pending          | Pending      | Pending  |
| Decoder                  | Pending          | Pending      | Pending  |
| RolesAuthority           | Pending          | Pending      | Pending  |
| TimelockController       | Pending          | Pending      | Pending  |

After broadcasting, verify that all five architecture addresses contain code, that
`HypoVaultFactory.hypoVaultReference()` returns
`0xF16714665955DBd0361D997eFc50fe391D96E8D0`, that the accountant uses the Robinhood WETH
address, and that the accountant and RolesAuthority are initially owned by the
broadcaster before updating this record.
