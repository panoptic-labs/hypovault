// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CollateralTrackerDecoderAndSanitizer} from "../src/DecodersAndSanitizers/CollateralTrackerDecoderAndSanitizer.sol";

/// @title CollateralTrackerDecoderAndSanitizer Deploy Script
/// @notice Script to deploy the CollateralTrackerDecoderAndSanitizer contract
contract DeployCollateralTrackerDecoderAndSanitizer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address hypoVault = 0x9f64DAB456351BF1488F7A02190BB532979721A7;

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
