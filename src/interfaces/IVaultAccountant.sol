// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Axicon Labs Limited
interface IVaultAccountant {
    /// @notice Returns the NAV of the portfolio contained in `vault` in terms of its underlying token
    /// @param vault The address of the vault to value
    /// @param depositToken The deposit token of the vault
    /// @param managerInput Additional input from the vault manager to be used in the accounting process, if applicable
    function computeNAV(
        address vault,
        address depositToken,
        bytes memory managerInput
    ) external view returns (uint256);

    /// @notice Returns the correct price of the proceedsToken in terms of the depositToken.
    /// @param vault The address of the vault to value
    /// @param depositToken The deposit token of the vault
    /// @param proceedsToken The proceeds token of the vault
    /// @param assetsRequested The total amount of assets to be converted
    /// @param managerInput Input calldata from the vault manager consisting of price quotes from the manager, pool information, and a position lsit for each pool
    function getTokenAmountsFromPrice(
        address vault,
        address depositToken,
        address proceedsToken,
        uint256 assetsRequested,
        bytes calldata managerInput
    ) external view returns (uint256, uint256);
}
