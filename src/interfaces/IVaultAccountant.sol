// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Axicon Labs Limited
interface IVaultAccountant {
    /// @notice Returns the NAV of the portfolio contained in `vault` in terms of its underlying token
    /// @param vault The address of the vault to value
    /// @param underlyingToken The underlying token of the vault
    /// @param managerInput Additional input from the vault manager to be used in the accounting process, if applicable
    function computeNAV(
        address vault,
        address underlyingToken,
        bytes memory managerInput
    ) external view returns (uint256);
}
