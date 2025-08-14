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
    /// @param depositToken The address of the deposit token
    /// @param proceedsToken The address of the proceeds token
    /// @param manager The address of the vault manager
    /// @param accountant The address of the vault accountant
    /// @param vault The address of the newly created vault
    /// @param performanceFeeBps The performance fee in basis points
    /// @param symbol The symbol of the share token
    /// @param name The name of the share token
    event VaultCreated(
        address indexed depositToken,
        address proceedsToken,
        address indexed manager,
        IVaultAccountant indexed accountant,
        address vault,
        uint256 performanceFeeBps,
        string symbol,
        string name
    );

    /*//////////////////////////////////////////////////////////////
                               FACTORY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new HypoVault instance.
    /// @param depositToken The token used to denominate deposits and withdrawals
    /// @param proceedsToken The alternative token used to denominate withdrawals
    /// @param manager The account authorized to execute deposits, withdrawals, and make arbitrary function calls from the vault
    /// @param accountant The contract that reports the net asset value of the vault
    /// @param performanceFeeBps The performance fee, in basis points, taken on each profitable withdrawal
    /// @param symbol The symbol of the share token
    /// @param name The name of the share token
    /// @return vault The address of the newly created vault
    function createVault(
        address depositToken,
        address proceedsToken,
        address manager,
        IVaultAccountant accountant,
        uint256 performanceFeeBps,
        string memory symbol,
        string memory name
    ) external returns (address vault) {
        vault = address(
            new HypoVault(
                depositToken,
                proceedsToken,
                manager,
                accountant,
                performanceFeeBps,
                symbol,
                name
            )
        );

        emit VaultCreated(
            depositToken,
            proceedsToken,
            manager,
            accountant,
            vault,
            performanceFeeBps,
            symbol,
            name
        );
    }
}
