// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";

/// @title HypoVaultFactory Deployment Script
/// @notice Script to deploy the HypoVaultFactory contract
contract DeployHypoVaultFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new HypoVaultFactory();

        vm.stopBroadcast();
    }
}
