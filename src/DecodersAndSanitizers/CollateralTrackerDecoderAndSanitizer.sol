// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "lib/boring-vault/src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

// Almost exactly like CollateralTrackerDecoderAndSanitizer, but adds additional withdraw signature
// for withdrawing with positions (additional positionIdList argument)
contract CollateralTrackerDecoderAndSanitizer is BaseDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) {}

    //============================== ERC4626 ===============================

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
        uint256[] calldata positionIdList
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

    //============================== PanopticPool ===============================

    function dispatch(
        uint256[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        int24[3][] calldata,
        bool,
        uint256
    ) external pure virtual returns (bytes memory addressesFound) {
        // No address arguments to extract
        return addressesFound;
    }

    //============================== WETH (NativeWrapper) ===============================

    function deposit() external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    function withdraw(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }
}
