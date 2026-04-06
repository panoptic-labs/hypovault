// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {HypoVault} from "../src/HypoVault.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {HypoVaultManagerWithMerkleVerification} from "../src/managers/HypoVaultManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";

// Transfers ownership of all mainnet contracts to the Panoptic multisig.
// Run AFTER all vaults are deployed.
// Usage: forge script script/TransferOwnershipToMultisig.s.sol --rpc-url mainnet --sender <addr> -vvvv --broadcast
contract TransferOwnershipToMultisig is Script {
    address constant MULTISIG = 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1;

    // Architecture
    address constant AUTHORITY = address(0); // fill in after deploy
    address constant ACCOUNTANT = address(0); // fill in after deploy

    // Vaults + Managers
    address constant WETH_VAULT = address(0); // fill in after deploy
    address constant WETH_MANAGER = address(0); // fill in after deploy
    address constant USDC_VAULT = address(0); // fill in after deploy
    address constant USDC_MANAGER = address(0); // fill in after deploy

    function run() public {
        console.log("=== Transfer Ownership to Multisig ===");
        console.log("Multisig:", MULTISIG);

        vm.startBroadcast();

        HypoVault(payable(WETH_VAULT)).transferOwnership(MULTISIG);
        console.log("WETH Vault ownership transferred");

        HypoVault(payable(USDC_VAULT)).transferOwnership(MULTISIG);
        console.log("USDC Vault ownership transferred");
        RolesAuthority(AUTHORITY).transferOwnership(MULTISIG);
        console.log("RolesAuthority ownership transferred");

        PanopticVaultAccountant(ACCOUNTANT).transferOwnership(MULTISIG);
        console.log("Accountant ownership transferred");

        vm.stopBroadcast();

        console.log("=== All Ownership Transferred ===");
    }
}
