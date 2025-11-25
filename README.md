## The HypoVault

The HypoVault is a smart contract that accepts funds from depositors and allows managers, permissioned by the HypoVaultManagerWithMerkleVerification, to take a limited set of actions on those funds. It uses asynchronous deposits and withdrawals to control the flow of funds, where managers are required to take action & fulfill your deposit or withdrawal.

Managers work with Accountant contracts to help each HypoVault arrive at a NAV and determine the share price credited to deposits & withdrawals. An Accountant specific to Panoptic can be found at `src/accountants/PanopticVaultAccountant.sol`.

More information can be found at the (in-progress) docs here: https://docs-git-feat-vault-section-panoptic.vercel.app/docs/vaults/overview

## Commands

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Deploy via EOA

To deploy with an EOA on Sepolia...

1. Ensure you .env is up to date:

```sh
PRIVATE_KEY=<private key>
ETHERSCAN_API_KEY=<your etherscan key>
ALCHEMY_API_KEY=<your alchemy key>
```

2. From the root of the repo, run

```
source .env && forge script --sender <sender for the private key in your env> --rpc-url https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY} script/DeployHypoVaultArchitectureEoa.s.sol -vvvv --broadcast --verify --slow`
```

> NOTE: Using a private key in a .env is not suitable for production. Forge script accepts the --turnkey option for deploying via Turnkey if we'd like to do an EOA deploy while maintaining high security guarantess. We may have to do this if the rabbit hole of Atomic Safe deployments continues to go deeper.

### Deploy via Safe

#### (ignore, not working currently)

To propose a deployment of an instance of the HypoVault architecture (HypoVaultFactory, PanopticVaultAccountant, HypoVault, HypoVaultManagerWithMerkleVerification,CollateralTrackerDecoderAndSanitizer, RolesAuthority), along with setting of relevant configuration like setting roles, setting supported pools and function calls for accounts with Curator roles, to a Safe, we can use the DeployHypoVaultArchitecture.s.sol script.

To run it, perform the following:

1. Ensure your dependencies are up to date

```sh
forge install
```

2. Ensure your `.env` is up to date

If you don't have a Safe transaction API key, you'll need to generate one here for the `SAFE_TX_API_KEY` env var: https://developer.safe.global/api-keys

Example for a ledger signer using account 9:

```sh
CHAIN=sepolia
WALLET_TYPE=ledger
MNEMONIC_INDEX=9
SAFE_TX_API_KEY=<your safe transaction service api key>
ALCHEMY_API_KEY=<your alchemy key>
```

3. Copy the deployment script and rename it to contain the vault you want to deploy. This ensure each vault deployment is stored in version control to look back later if we need it for anything (like to regenerate the merkle tree containing allowlisted functions).

4. Double check the addresses are correct inside the script
   For the WETH PLP Vault,
   The PanopticMultisig is: `0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1`
   The Turnkey manager account is: `0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8` (new vaults will need a new account)

5. Run the script to propose the deployment transaction to the safe!

```sh
source .env && forge script --ffi --sender 0xb0300f0f038d7075e8e627e0d22d5786d59121ab --rpc-url https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY} script/DeployHypoVaultArchitecture.s.sol true
```

6. Commit your new script and the `.json` file that was written in the `leafs/` directory and push to a branch on GitHub.

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
