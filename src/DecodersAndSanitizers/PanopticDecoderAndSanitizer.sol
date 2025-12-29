// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "lib/boring-vault/src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

/// @title PanopticDecoderAndSanitizer
/// @notice Decoder and sanitizer for Panoptic HypoVault operations including CollateralTracker and manager functions
contract PanopticDecoderAndSanitizer is BaseDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    //============================== PANOPTIC POOL ===============================
    // TODO:

    //============================== COLLATERAL TRACKER ===============================

    function deposit(
        uint256,
        address receiver
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    function mint(
        uint256,
        address receiver
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    function withdraw(
        uint256,
        address receiver,
        address owner
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver, owner);
    }

    function withdraw(
        uint256,
        address receiver,
        address owner,
        uint256[] calldata
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver, owner);
    }

    function redeem(
        uint256,
        address receiver,
        address owner
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver, owner);
    }

    //============================== HYPOVAULT MANAGER ===============================

    /// @notice Decoder for HypoVaultManagerWithMerkleVerification.fulfillDeposits
    /// @dev No address arguments to extract
    function fulfillDeposits(
        uint256,
        bytes memory
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = "";
    }

    /// @notice Decoder for HypoVaultManagerWithMerkleVerification.fulfillWithdrawals
    /// @dev No address arguments to extract
    function fulfillWithdrawals(
        uint256,
        uint256,
        bytes memory
    ) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = "";
    }
}
