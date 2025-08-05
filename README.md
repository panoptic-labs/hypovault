## The HypoVault

The HypoVault is a smart contract that accepts funds from depositors and allows managers, permissioned by the HypovaultManagerWithMerkleVerification, to take a limited set of actions on those funds. It uses asynchronous deposits and withdrawals to control the flow of funds, where managers are required to take action & fulfill your deposit or withdrawal.

In-progress docs: https://docs-git-feat-vault-section-panoptic.vercel.app/docs/vaults/overview

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
