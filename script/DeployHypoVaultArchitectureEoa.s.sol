// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {HypoVault} from "../src/HypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import "../src/accountants/PanopticVaultAccountant.sol";
import {Script} from "forge-std/Script.sol";

// import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";

// Intended to be run from an EOA using vm.startBroadcast/stopBroadcast
// contract DeployHypoVaultArchitectureEoa is DeployHypoVault {
contract DeployHypoVaultArchitectureEoa is Script {
    // CREATE2 salt
    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v7"));
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

    function run() public {
        console.log("=== Deployer Address ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy reference HypoVault implementation with CREATE2
        HypoVault hypoVaultImpl = new HypoVault{salt: salt}();
        address hypoVaultImplAddress = address(hypoVaultImpl);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("HypoVault implementation Address:", hypoVaultImplAddress);

        // 2. Deploy HypoVaultFactory with CREATE2
        HypoVaultFactory vaultFactory = new HypoVaultFactory{salt: salt}(hypoVaultImplAddress);
        address vaultFactoryAddress = address(vaultFactory);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Factory Address:", vaultFactoryAddress);

        // 3. Deploy new Accountant with CREATE2
        PanopticVaultAccountant accountant = new PanopticVaultAccountant{salt: salt}(deployer);
        address accountantAddress = address(accountant);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Accountant Address:", accountantAddress);

        // 4. Deploy WETH vault
        // deployVault(
        // address(vaultFactory),
        // address(accountant),
        // address(sepoliaWeth),
        // "povLendWETH",
        // "Panoptic Lend Vault | WETH",
        // salt
        // );

        vm.stopBroadcast();

        console.log("=== Full Architecture Deployment Complete ===");
        console.log("HypoVault Implementation:", hypoVaultImplAddress);
        console.log("Factory:", vaultFactoryAddress);
        console.log("Accountant:", accountantAddress);

        // TODO: be mindful msg sender is deployer still. transfer deployership if necessary
    }
}
