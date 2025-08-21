// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import "../interfaces/IHypoVault.sol";

/// @title HypoVaultManagerWithMerkleVerification
/// @notice Extends boring-vault's ManagerWithMerkleVerification with HypoVault-specific management functions
/// @dev Inherits merkle tree verification for secure function calls while adding HypoVault operations
contract HypoVaultManagerWithMerkleVerification is ManagerWithMerkleVerification {
    //============================== ERRORS ===============================

    error HypovaultManager__Unauthorized();

    //============================== MODIFIERS ===============================

    /// @notice Modifier that restricts access to curators (addresses with merkle roots) or owner
    modifier onlyStrategist() {
        if (manageRoot[msg.sender] == bytes32(0) && msg.sender != owner) {
            revert HypovaultManager__Unauthorized();
        }
        _;
    }

    constructor(
        address _owner,
        address _hypovault,
        address _balancerVault
    ) ManagerWithMerkleVerification(_owner, _hypovault, _balancerVault) {}

    /*//////////////////////////////////////////////////////////////
                        HYPOVAULT MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cancels a deposit in the current (unfulfilled) epoch
    /// @param depositor The address that requested the deposit
    function cancelDeposit(address depositor) external onlyStrategist {
        IHypoVault(address(vault)).cancelDeposit(depositor);
    }

    /// @notice Cancels a withdrawal in the current (unfulfilled) epoch
    /// @param withdrawer The address that requested the withdrawal
    function cancelWithdrawal(address withdrawer) external onlyStrategist {
        IHypoVault(address(vault)).cancelWithdrawal(withdrawer);
    }

    /// @notice Requests a withdrawal from any user with redeposit option
    /// @param user The user to initiate the withdrawal from
    /// @param shares The amount of shares to withdraw
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    function requestWithdrawalFrom(
        address user,
        uint128 shares,
        bool shouldRedeposit
    ) external onlyStrategist {
        IHypoVault(address(vault)).requestWithdrawalFrom(user, shares, shouldRedeposit);
    }

    /// @notice Fulfills deposit requests
    /// @param assetsToFulfill The amount of assets to fulfill
    /// @param managerInput Arbitrary input to the accountant contract
    function fulfillDeposits(
        uint256 assetsToFulfill,
        bytes memory managerInput
    ) external onlyStrategist {
        IHypoVault(address(vault)).fulfillDeposits(assetsToFulfill, managerInput);
    }

    /// @notice Fulfills withdrawal requests
    /// @param sharesToFulfill The amount of shares to fulfill
    /// @param maxAssetsReceived The maximum amount of assets willing to disburse
    /// @param managerInput Arbitrary input to the accountant contract
    function fulfillWithdrawals(
        uint256 sharesToFulfill,
        uint256 maxAssetsReceived,
        bytes memory managerInput
    ) external onlyStrategist {
        IHypoVault(address(vault)).fulfillWithdrawals(
            sharesToFulfill,
            maxAssetsReceived,
            managerInput
        );
    }
}
