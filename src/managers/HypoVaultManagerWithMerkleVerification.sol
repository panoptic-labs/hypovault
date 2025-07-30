// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import "../interfaces/IHypoVault.sol";

/// @title HypovaultManagerWithMerkleVerification
/// @notice Extends boring-vault's ManagerWithMerkleVerification with HypoVault-specific management functions
/// @dev Inherits merkle tree verification for secure function calls while adding HypoVault operations
contract HypovaultManagerWithMerkleVerification is ManagerWithMerkleVerification {
    /// @notice The HypoVault this manager operates on
    IHypoVault public immutable hypovault;

    constructor(
        address _owner,
        address _hypovault,
        address _balancerVault
    ) ManagerWithMerkleVerification(_owner, _hypovault, _balancerVault) {
        hypovault = IHypoVault(_hypovault);
    }

    /*//////////////////////////////////////////////////////////////
                        HYPOVAULT MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cancels a deposit in the current (unfulfilled) epoch
    /// @param depositor The address that requested the deposit
    function cancelDeposit(address depositor) external requiresAuth {
        hypovault.cancelDeposit(depositor);
    }

    /// @notice Cancels a withdrawal in the current (unfulfilled) epoch
    /// @param withdrawer The address that requested the withdrawal
    function cancelWithdrawal(address withdrawer) external requiresAuth {
        hypovault.cancelWithdrawal(withdrawer);
    }

    /// @notice Requests a withdrawal from any user with redeposit option
    /// @param user The user to initiate the withdrawal from
    /// @param shares The amount of shares to withdraw
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    function requestWithdrawalFrom(
        address user,
        uint128 shares,
        bool shouldRedeposit
    ) external requiresAuth {
        hypovault.requestWithdrawalFrom(user, shares, shouldRedeposit);
    }

    /// @notice Fulfills deposit requests
    /// @param assetsToFulfill The amount of assets to fulfill
    /// @param managerInput Arbitrary input to the accountant contract
    function fulfillDeposits(
        uint256 assetsToFulfill,
        bytes memory managerInput
    ) external requiresAuth {
        hypovault.fulfillDeposits(assetsToFulfill, managerInput);
    }

    /// @notice Fulfills withdrawal requests
    /// @param sharesToFulfill The amount of shares to fulfill
    /// @param maxAssetsReceived The maximum amount of assets willing to disburse
    /// @param managerInput Arbitrary input to the accountant contract
    function fulfillWithdrawals(
        uint256 sharesToFulfill,
        uint256 maxAssetsReceived,
        bytes memory managerInput
    ) external requiresAuth {
        hypovault.fulfillWithdrawals(sharesToFulfill, maxAssetsReceived, managerInput);
    }

    // TODO: If we wanted the ability to skip merkle verification, we could have these methods:
    // though at that point, it makes less sense for this contract to be a child of ManagerWithMerkleVerification, and more sense
    // to just fork ManagerWithMerkleVerification and remove the merkle verification parts + add the above methods
    /*
    /// @notice Makes an arbitrary function call from the HypoVault contract
    /// @param target The target contract to call
    /// @param data The calldata to send
    /// @param value The ETH value to send
    function manageHypovault(
        address target,
        bytes calldata data,
        uint256 value
    ) external requiresAuth returns (bytes memory result) {
        return hypovault.manage(target, data, value);
    }

    /// @notice Makes arbitrary function calls from the HypoVault contract
    /// @param targets The target contracts to call
    /// @param data The calldata to send to each target
    /// @param values The ETH values to send to each target
    function manageHypovaultBatch(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external requiresAuth returns (bytes[] memory results) {
        return hypovault.manage(targets, data, values);
    }
    */
}
