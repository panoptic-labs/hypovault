// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DeployArchitecture} from "./helpers/DeployArchitecture.sol";
import {ChainConfig} from "./helpers/ChainConfig.sol";

// Deploys core HypoVault infrastructure using --private-key or --turnkey --sender 0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8 (Turnkey0)
// Usage: CHAIN_NAME=sepolia forge script script/DeployHypoVaultArchitectureEoa.s.sol --rpc-url sepolia --sender <addr> -vvvv --broadcast --verify
contract DeployHypoVaultArchitectureEoa is Script, DeployArchitecture, ChainConfig {
    // CREATE2 salt
    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v17"));

    function run() public {
        Config memory c = getChainConfig();

        vm.startBroadcast();

        address deployer = msg.sender;
        (
            address hypoVaultImplAddress,
            address vaultFactoryAddress,
            address accountantAddress,
            address collateralTrackerDecoderAndSanitizerAddress,
            address authorityAddress
        ) = deployArchitecture(salt, deployer, c.weth);

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
