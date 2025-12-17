// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";

contract DeployUSDCVault is DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0x6305aacd3d046B09bf991314031c59B1EFEEE12B);
    address constant ACCOUNTANT_ADDRESS = address(0x4d05d5396D13E40B1b868BfF883696A45682ca9B);

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
