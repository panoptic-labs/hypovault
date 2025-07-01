// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HypoVault} from "./HypoVault.sol";
import {IVaultAccountant} from "./interfaces/IVaultAccountant.sol";

/// @title HypoVault Factory
/// @author Axicon Labs Limited
/// @notice Factory contract for creating HypoVault instances
contract HypoVaultFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a vault is created.
    /// @param underlyingToken The address of the underlying token
    /// @param manager The address of the vault manager
    /// @param accountant The address of the vault accountant
    /// @param vault The address of the newly created vault
    /// @param performanceFeeBps The performance fee in basis points
    event VaultCreated(
        address indexed underlyingToken,
        address indexed manager,
        IVaultAccountant indexed accountant,
        address vault,
        uint256 performanceFeeBps
    );

    /*//////////////////////////////////////////////////////////////
                               FACTORY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new HypoVault instance.
    /// @param underlyingToken The token used to denominate deposits and withdrawals
    /// @param manager The account authorized to execute deposits, withdrawals, and make arbitrary function calls from the vault
    /// @param accountant The contract that reports the net asset value of the vault
    /// @param performanceFeeBps The performance fee, in basis points, taken on each profitable withdrawal
    /// @return vault The address of the newly created vault
    function createVault(
        address underlyingToken,
        address manager,
        IVaultAccountant accountant,
        uint256 performanceFeeBps
    ) external returns (address vault) {
        vault = address(new HypoVault(underlyingToken, manager, accountant, performanceFeeBps));

        emit VaultCreated(underlyingToken, manager, accountant, vault, performanceFeeBps);
    }
}
