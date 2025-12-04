# Overview

The `HypoVault` is based on DeFi thoroughly audited smart contract suite for vault infrastructure built by [Veda](https://veda.tech/). Instantiations of their smart contracts manage over 2 Billion in assets across DeFi and have been used by 100K+ unique accounts.

Our innovation has been the `HypoVault`, which allows for asynchronous deposits and withdrawals, while maintaining the core security guarantees of the rest of Veda's vault architecture. The core security guarantees come from a specific contract, `ManagerWithMerkleVerification`.

The following diagrams illustrate how we modified the vault architecture to suit Panoptic's options vaults, and how the core security guarantees of `ManagerWithMerkleVerification` protect depositors from malicious vault manager actions.

> The charts can be viewed in VSCode using the "Mermaid Chart" extension, or in the browser by copying and pasting the chart code into https://mermaid.live/, or https://excalidraw.com/ with Excalidraw's Mermaid -> Excalidraw feature.

## HypoVault Architecture Class Diagram

A selection of important contracts in the HypoVault architecture:

```mermaid
classDiagram
    class HypoVaultFactory {
        +address hypoVaultReference
        +createVault(...)
    }

    class HypoVault {
        +address underlyingToken
        +address manager
        +IVaultAccountant accountant
        +address feeWallet
        +uint128 withdrawalEpoch
        +uint128 depositEpoch
        +requestDeposit()
        +requestWithdrawal()
        +executeDeposit()
        +executeWithdrawal()
        +fulfillDeposits()
        +fulfillWithdrawals()
        +manage()
        +setManager()
        +setAccountant()
    }

    class HypoVaultManagerWithMerkleVerification {
        +cancelDeposit()
        +cancelWithdrawal()
        +requestWithdrawalFrom()
        +fulfillDeposits()
        +fulfillWithdrawals()
    }

    class ManagerWithMerkleVerification {
        +BoringVault vault
        +BalancerVault balancerVault
        +mapping manageRoot
        +bool isPaused
        +manageVaultWithMerkleVerification()
        +setManageRoot()
        +pause()
        +unpause()
        +flashLoan()
    }

    class DecoderAndSanitizer {
        <<utility>>
        +functionStaticCall(targetData) returns bytes
    }

    class Auth {
        <<abstract>>
        +address owner
        +Authority authority
        +requiresAuth()
        +transferOwnership()
        +setAuthority()
    }

    class Authority {
        <<interface>>
        +canCall(user, target, functionSig) bool
    }

    class IVaultAccountant {
        <<interface>>
        +computeNAV(vault, underlyingToken, managerInput) uint256
    }

    class PanopticVaultAccountant {
        +mapping vaultPools
        +mapping vaultLocked
        +computeNAV()
        +updatePoolsHash()
        +lockVault()
    }

    class OwnableUpgradeable {
        <<abstract>>
        +address owner
        +onlyOwner()
    }

    HypoVaultFactory "1" --> "*" HypoVault : creates
    HypoVault --> IVaultAccountant : uses
    HypoVault --> HypoVaultManagerWithMerkleVerification : managed by
    HypoVault --|> OwnableUpgradeable

    HypoVaultManagerWithMerkleVerification --|> ManagerWithMerkleVerification
    HypoVaultManagerWithMerkleVerification --> HypoVault : manages

    ManagerWithMerkleVerification --|> Auth
    ManagerWithMerkleVerification "1" --> "1" BoringVault : manages
    ManagerWithMerkleVerification ..> DecoderAndSanitizer : uses during manageVaultWithMerkleVerification()

    Auth --> Authority : optional

    PanopticVaultAccountant ..|> IVaultAccountant

    note for ManagerWithMerkleVerification "manageRoot: strategist => merkle root\nAllows per-strategist call auth"
    note for DecoderAndSanitizer "Only needed when calling\nmanageVaultWithMerkleVerification:\nused to extract & sanitize addresses\nfor Merkle proof verification"
```

## HypoVault Deposit & Manage Sequence Diagrams

An example of async deposit flow through the HypoVault, followed by a manager depositing the user's assets in a CollateralTracker to earn yield.

When viewing the manage flows, it's useful to keep in mind the structure of the leaves which create the merkle root:

```solidity
struct ManageLeaf {
  address target; // contract being called
  bool canSendValue; // whether the call is allowed to forward native assets
  string signature; // (a.k.a selector) human-readable function signature
  address[] argumentAddresses; // sanitized address args extracted from calldata
  string description; // helper metadata when exporting trees to JSON
  address decoderAndSanitizer; // bespoke helper that extracts & sanitizes addresses for this target/signature
}
```

> This structure can be observed in the function `ManagerWithMerkleVerification._verifyManageProof`, and the struct is defined explicitly in the `MerkleTreeHelper` contract, which is used to build merkle roots and export a human-readable merkle tree to a JSON file for managers to build valid calls.

The following sequence diagrams are simplified to help you get your bearings on how the vault architecture works. They assume a single merkle root consisting of a single merkle leaf, and a single manager. In practice, there can be many merkle roots, many managers, and many leaves per merkle root. Additionally, the merkle roots can be updated by accounts specified using the Authority contract shown in the class diagram above. These details are not shown.

### Happy Path – Deposit Request & Manage call to deposit to Collateral Tracker

Merkle tree configuration for this flow:

- target: `WethCollateralTracker`
- decoder/sanitizer: `CollateralTrackerDecoderAndSanitizer`
- signature: `ERC4626.deposit(uint256 assets, address receiver)`
- canSendValue: `false`
- argument addresses: `{HypoVault}`

```mermaid
sequenceDiagram
    autonumber
    participant Alice as Alice (User)
    participant HypoVault as HypoVault
    participant Manager as TurnkeySigner (Manager)
    participant MerkleMgr as HypoVaultManager<br/>WithMerkleVerification
    participant WethCollateralTracker as Panoptic WethCollateralTracker<br/>(ERC4626)

    Alice->>HypoVault: requestDeposit(assets)
    HypoVault-->>Alice: emit DepositRequested
    HypoVault->>HypoVault: queue assets for depositEpoch

    Manager->>HypoVault: fulfillDeposits(assetsToFulfill, managerInput)
    HypoVault->>HypoVault: compute sharesReceived via accountant
    HypoVault-->>Manager: emit DepositsFulfilled

    Manager->>MerkleMgr: manageVaultWithMerkleVerification(proofs, decoders, targets, targetData, values)
    MerkleMgr->>MerkleMgr: verify merkle proof using DecoderAndSanitizer
    MerkleMgr->>HypoVault: manage(target=WethCollateralTracker, data=ERC4626.deposit(50 ether, wethPlpVault), value=0)
    HypoVault->>WethCollateralTracker: deposit(50 ether, receiver=wethPlpVault)
    WethCollateralTracker-->>HypoVault: mint collateral shares
    HypoVault-->>MerkleMgr: manage() result
    MerkleMgr-->>Manager: emit BoringVaultManaged*Target data reference:* `abi.encodeWithSelector(ERC4626.deposit.selector, 50 ether, wethPlpVault)` (`test/deployment/PLPVaultIntegrationTest.t.sol`, lines 425‑430).
```

### Bad Path – Manager attempts to call an unauthorized target

Merkle tree configuration for this flow:

- target: `WethCollateralTracker`
- decoder/sanitizer: `CollateralTrackerDecoderAndSanitizer`
- signature: `ERC4626.deposit(uint256 assets, address receiver)`
- canSendValue: `false`
- argument addresses: `{HypoVault}`

```mermaid
sequenceDiagram
    autonumber
    participant Strategist as MaliciousStrategist
    participant MerkleMgr as HypoVaultManager<br/>WithMerkleVerification
    participant Decoder as DecoderAndSanitizer
    participant HypoVault as HypoVault
    participant KimJongUnCoinCollateralTracker as KimJongUnCoinCollateralTracker

    Strategist->>MerkleMgr: manageVaultWithMerkleVerification(..., target=KimJongUnCoinCollateralTracker, data=ERC4626.deposit(..., receiver=HypoVault))
    MerkleMgr->>Decoder: functionStaticCall(targetData)
    Decoder-->>MerkleMgr: packed addresses (HypoVault)
    MerkleMgr->>MerkleMgr: _verifyManageProof(root, proof, KimJongUnCoinCollateralTracker, decoder, value, selector, packedAddresses)
    MerkleMgr-->>Strategist: revert FailedToVerifyManageProof(KimJongUnCoinCollateralTracker, targetData, 0)
    Strategist-xHypoVault: call aborted (manage not executed)
    note over MerkleMgr,Strategist: Revert occurs before HypoVault.manage because the target isn’t authorized even though the argument address (HypoVault) is.
```

### Mixed Path – Manager calls allowed target with allowed argument addresses, then disallowed argument addresses

Merkle tree configuration for this flow:

- target: `UniswapRouter02`
- decoder/sanitizer: `UniswapRouterDecoderAndSanitizer`
- signature: `swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)`
- canSendValue: `true`
- argument addresses: `{UsdcWeth500Bps, UsdcUsdt10Bps, HypoVault}`

```mermaid
sequenceDiagram
    autonumber
    participant Strategist
    participant MerkleMgr as HypoVaultManager<br/>WithMerkleVerification
    participant Decoder as UniswapRouterDecoderAndSanitizer
    participant HypoVault
    participant Router as UniswapRouter02
    participant PoolA as UsdcWeth500Bps
    participant PoolB as UsdcUsdt10Bps
    participant RugPool as RugV3Pool

    note over Strategist,RugPool: swapExactTokensForTokens(... path[], to, deadline)\ncanSendValue = true

    rect rgb(219,255,219)
        note over Strategist,Router: Valid swap (leaf authorizes Router02 + {PoolA, PoolB, HypoVault})
        Strategist->>MerkleMgr: manageVaultWithMerkleVerification(... target=Router02 ...)
        MerkleMgr->>Decoder: functionStaticCall(targetData)
        Decoder-->>MerkleMgr: packed addresses = {PoolA, PoolB, HypoVault}
        MerkleMgr->>MerkleMgr: _verifyManageProof(root, proof, Router02, decoder, 0, selector, packedAddresses)
        MerkleMgr->>HypoVault: manage(target=Router02, data=swapExactTokensForTokens(PoolA→PoolB, to=HypoVault))
        HypoVault->>Router: swapExactTokensForTokens(...)
        Router->>PoolA: pull USDC
        PoolA->>PoolB: route to USDT
        Router-->>HypoVault: returns output tokens (deposited to HypoVault)
        MerkleMgr-->>Strategist: success
    end

    rect rgb(255,228,225)
        note over Strategist,RugPool: Invalid swap (RugPool not in leaf arg addresses)
        Strategist->>MerkleMgr: manageVaultWithMerkleVerification(... data references RugPool ...)
        MerkleMgr->>Decoder: functionStaticCall(targetData)
        Decoder-->>MerkleMgr: packed addresses = {PoolA, RugPool, HypoVault}
        MerkleMgr->>MerkleMgr: _verifyManageProof(...) fails (RugPool ∉ allowed addresses)
        MerkleMgr-->>Strategist: revert FailedToVerifyManageProof(Router02, targetData, 0)
        Strategist-xHypoVault: call never reaches HypoVault.manage
    end
```
