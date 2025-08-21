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

### Deploy

Need to write the deploy script first, but will eventually be something like:

```shell
$ forge script script/DeployHypoVault.s.sol:DeployHypoVault --rpc-url <your_rpc_url> --private-key <your_private_key>
```

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
