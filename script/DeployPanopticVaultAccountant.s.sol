// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";

/// @title PanopticVaultAccountantn Deploy Script
/// @notice Script to deploy the PanopticVaultAccountant contract
contract DeployPanopticVaultAccountant is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new PanopticVaultAccountant();

        vm.stopBroadcast();
    }
}
