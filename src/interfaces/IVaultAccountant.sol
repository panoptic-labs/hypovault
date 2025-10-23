// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Axicon Labs Limited
interface IVaultAccountant {
    /// @notice Returns the NAV of the portfolio contained in `vault` in terms of its underlying token.
    /// @param vault The address of the vault to value
    /// @param depositToken The underlying deposit token of the vault
    /// @param proceedsToken The underlying proceeds token of the vault
    /// @param reservedDepositAssets Amount of deposit token reserved to be withdrawn
    /// @param reservedProceedsAssets Amount of proceeds token reserved to be withdrawn
    /// @param managerInput Input calldata from the vault manager consisting of price quotes from the manager, pool information, and a position lsit for each pool
    /// @return nav The NAV of the portfolio contained in `vault` in terms of its underlying token
    /// @return depositBalance The balance of deposit tokens owned by the vault
    /// @return proceedsBalance The balance of proceeds tokens owned by the vault
    function computeNAV(
        address vault,
        address depositToken,
        address proceedsToken,
        uint256 reservedDepositAssets,
        uint256 reservedProceedsAssets,
        bytes calldata managerInput
    ) external view returns (uint256, uint256, uint256);
}
