// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HypoVault} from "../src/HypoVault.sol";
import {IVaultAccountant} from "../src/interfaces/IVaultAccountant.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {HypoVaultManagerWithMerkleVerification} from "../src/managers/HypoVaultManagerWithMerkleVerification.sol";

/// @title HypoVault Deployment Script
/// @notice Script to deploy the HypoVault contract
contract DeployHypoVault is Script {
    function run() external {
        // address vault = _deployVault();

        address vault = 0x9f64DAB456351BF1488F7A02190BB532979721A7;
        address owner = 0x7643c4F21661691fb851AfedaF627695672C9fac;
        address strategist = 0x7643c4F21661691fb851AfedaF627695672C9fac;
        HypoVaultManagerWithMerkleVerification manager = _deployManagerWithMerkleVerification(
            owner,
            vault
        );

        bytes32 plpDepositManageRoot = 0x9966a2cae2ebd152f6d786cb4bebb65625f23a7abe4ce11d7ad9de2628febaf3;
        manager.setManageRoot(strategist, plpDepositManageRoot);

        vm.stopBroadcast();
    }

    function _deployVault() private returns (address vault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address SEPOLIA_WETH_ADDR = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address underlyingToken = SEPOLIA_WETH_ADDR;

        address manager = msg.sender;

        // Sepolia-deployed PanopticVaultAccountant
        address accountant = 0x09CdD3f95BfB6879065ce18d1d95A6db07b987D7;

        uint256 performanceFeeBps = 1000;

        vm.startBroadcast(deployerPrivateKey);

        HypoVaultFactory factory = HypoVaultFactory(0x51Bb423d38C6D347206234C160C28384A17cBe8e);

        vault = factory.createVault(
            underlyingToken,
            manager,
            IVaultAccountant(accountant),
            performanceFeeBps,
            "FTX",
            "The Polycule"
        );
    }

    function _deployManagerWithMerkleVerification(
        address owner,
        address hypoVault
    ) private returns (HypoVaultManagerWithMerkleVerification manager) {
        manager = new HypoVaultManagerWithMerkleVerification(owner, hypoVault, address(0));
    }
}
