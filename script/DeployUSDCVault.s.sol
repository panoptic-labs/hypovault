// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";

contract DeployUSDCVault is DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0xAC387fD49d0031529235dEf909C70522AD7655b6);
    address constant ACCOUNTANT_ADDRESS = address(0xb50E60c7f2c57735C48166a612143649Cd143e49);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v6-usdc"));

    // Sepolia USDC address
    IERC20Partial sepoliaUsdc = IERC20Partial(0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A);

    function run() public {
        console.log("=== Deploying USDC Vault ===");
        console.log("Deployer:", deployer);
        console.log("Using Factory:", FACTORY_ADDRESS);
        console.log("Using Accountant:", ACCOUNTANT_ADDRESS);

        require(FACTORY_ADDRESS != address(0), "Factory address not set");
        require(ACCOUNTANT_ADDRESS != address(0), "Accountant address not set");

        vm.startBroadcast(deployerPrivateKey);

        deployVault(
            FACTORY_ADDRESS,
            ACCOUNTANT_ADDRESS,
            address(sepoliaUsdc),
            "povLendUSDC",
            "Panoptic Lend Vault | USDC",
            salt
        );

        vm.stopBroadcast();
    }
}
