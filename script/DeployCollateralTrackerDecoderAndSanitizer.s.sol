// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CollateralTrackerDecoderAndSanitizer} from "../src/DecodersAndSanitizers/CollateralTrackerDecoderAndSanitizer.sol";

/// @title CollateralTrackerDecoderAndSanitizer Deploy Script
/// @notice Script to deploy the CollateralTrackerDecoderAndSanitizer contract
contract DeployCollateralTrackerDecoderAndSanitizer is Script {
    function run() external {
        vm.startBroadcast();

        address hypoVault = 0x265933ff1C1ebf01b7Ae66c2Ca68B9023f286849;

        CollateralTrackerDecoderAndSanitizer decoderAndSanitizer = new CollateralTrackerDecoderAndSanitizer(
                hypoVault
            );

        console.log(
            "CollateralTrackerDecoderAndSanitizer deployed at:",
            address(decoderAndSanitizer)
        );

        vm.stopBroadcast();
    }
}
