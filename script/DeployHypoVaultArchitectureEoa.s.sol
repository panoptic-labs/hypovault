// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DeployArchitecture} from "./helpers/DeployArchitecture.sol";

// Deploys core HypoVault infrastructure using --private-key or --turnkey
contract DeployHypoVaultArchitectureEoa is Script, DeployArchitecture {
    // CREATE2 salt
    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9"));

    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;
        (
            address hypoVaultImplAddress,
            address vaultFactoryAddress,
            address accountantAddress,
            address collateralTrackerDecoderAndSanitizerAddress,
            address authorityAddress
        ) = deployArchitecture(salt, deployer);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("HypoVault Implementation:", hypoVaultImplAddress);
        console.log("Factory:", vaultFactoryAddress);
        console.log("Accountant:", accountantAddress);
        console.log(
            "CollateralTrackerDecoderAndSanitizer:",
            collateralTrackerDecoderAndSanitizerAddress
        );
        console.log("RolesAuthority:", authorityAddress);
    }
}
