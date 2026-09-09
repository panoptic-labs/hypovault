# Robinhood Chain deterministic architecture deployment

This runbook deploys only the production `HypoVault` implementation and
`HypoVaultFactory`. It must not create vault instances.

## Network and deployment inputs

| Input | Value |
| --- | --- |
| Chain ID | `4663` |
| RPC alias | `robinhood` |
| Explorer | `https://robinhoodchain.blockscout.com` |
| CREATE2 deployer | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Broadcast sender | `0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8` |
| Salt | `0xe78b3302c1a713353b49c40fcbd176c072797bfcd948b809b61bf8fd3216ea8b` |
| HypoVault implementation | `0xF16714665955DBd0361D997eFc50fe391D96E8D0` |
| HypoVaultFactory | `0xd5049B2647de57141dE7F65E5124707B99A452A3` |

Configure the Alchemy endpoint without committing its API key:

```sh
export ROBINHOOD_ALCHEMY_API_KEY='<key>'
```

## Pre-broadcast procedure

1. Confirm the sender has at least `0.01 ETH` on Robinhood Chain.
2. Run the deterministic deployment tests:

   ```sh
   forge test --match-contract RobinhoodDeterministicDeploymentTest -vv
   ```

3. Run a simulation and inspect the two predicted addresses:

   ```sh
   forge script script/DeployHypoVaultArchitectureRobinhood.s.sol \
     --rpc-url robinhood \
     --sender 0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8 \
     -vvvv
   ```

4. Recheck that the canonical deployer has code and both target addresses are empty.
5. Obtain explicit approval before adding `--broadcast`.

For broadcast, use `--slow` so the implementation transaction is confirmed before the
factory transaction is sent. Do not add `--broadcast` during preparation or review.

After both receipts are successful, run the read-only live verification:

```sh
forge script script/VerifyHypoVaultArchitectureRobinhood.s.sol \
  --rpc-url robinhood \
  -vv
```

## Deployment record

Status: **Not broadcast**

| Contract | Transaction hash | Block number | Gas used |
| --- | --- | --- | --- |
| HypoVault implementation | Pending | Pending | Pending |
| HypoVaultFactory | Pending | Pending | Pending |

After broadcasting, verify that both addresses contain code and that
`HypoVaultFactory.hypoVaultReference()` returns
`0xF16714665955DBd0361D997eFc50fe391D96E8D0` before updating this record.
