// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {RolesAuthority} from "../lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {RobinhoodDeploymentConfig as Config} from "./helpers/RobinhoodDeploymentConfig.sol";

/// @notice Read-only live verification for the Robinhood architecture deployment.
contract VerifyHypoVaultArchitectureRobinhood is Script {
    error AuthorityMismatch(address actual, address expected);
    error MissingCode(address target);
    error OwnerMismatch(address actual, address expected);
    error ReferenceMismatch(address actual, address expected);
    error UnexpectedChainId(uint256 actual, uint256 expected);
    error WethMismatch(address actual, address expected);

    function run() public view {
        if (block.chainid != Config.CHAIN_ID) {
            revert UnexpectedChainId(block.chainid, Config.CHAIN_ID);
        }
        if (Config.HYPO_VAULT_IMPLEMENTATION.code.length == 0) {
            revert MissingCode(Config.HYPO_VAULT_IMPLEMENTATION);
        }
        if (Config.HYPO_VAULT_FACTORY.code.length == 0) {
            revert MissingCode(Config.HYPO_VAULT_FACTORY);
        }
        if (Config.ACCOUNTANT.code.length == 0) revert MissingCode(Config.ACCOUNTANT);
        if (Config.DECODER.code.length == 0) revert MissingCode(Config.DECODER);
        if (Config.ROLES_AUTHORITY.code.length == 0) revert MissingCode(Config.ROLES_AUTHORITY);

        address hypoVaultReferenceAddress = HypoVaultFactory(Config.HYPO_VAULT_FACTORY)
            .hypoVaultReference();
        if (hypoVaultReferenceAddress != Config.HYPO_VAULT_IMPLEMENTATION) {
            revert ReferenceMismatch(hypoVaultReferenceAddress, Config.HYPO_VAULT_IMPLEMENTATION);
        }

        PanopticVaultAccountant accountant = PanopticVaultAccountant(Config.ACCOUNTANT);
        if (accountant.owner() != Config.BROADCASTER) {
            revert OwnerMismatch(accountant.owner(), Config.BROADCASTER);
        }
        if (accountant.wethAddress() != Config.WETH) {
            revert WethMismatch(accountant.wethAddress(), Config.WETH);
        }

        RolesAuthority rolesAuthority = RolesAuthority(Config.ROLES_AUTHORITY);
        if (rolesAuthority.owner() != Config.BROADCASTER) {
            revert OwnerMismatch(rolesAuthority.owner(), Config.BROADCASTER);
        }
        if (address(rolesAuthority.authority()) != address(0)) {
            revert AuthorityMismatch(address(rolesAuthority.authority()), address(0));
        }

        console2.log("=== Robinhood HypoVault live verification ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("HypoVault implementation:", Config.HYPO_VAULT_IMPLEMENTATION);
        console2.log("HypoVault implementation code hash:");
        console2.logBytes32(Config.HYPO_VAULT_IMPLEMENTATION.codehash);
        console2.log("HypoVaultFactory:", Config.HYPO_VAULT_FACTORY);
        console2.log("HypoVaultFactory code hash:");
        console2.logBytes32(Config.HYPO_VAULT_FACTORY.codehash);
        console2.log("HypoVaultFactory reference:", hypoVaultReferenceAddress);
        console2.log("PanopticVaultAccountant:", Config.ACCOUNTANT);
        console2.log("PanopticVaultAccountant owner:", accountant.owner());
        console2.log("PanopticVaultAccountant WETH:", accountant.wethAddress());
        console2.log("CollateralTrackerDecoderAndSanitizer:", Config.DECODER);
        console2.log("RolesAuthority:", Config.ROLES_AUTHORITY);
        console2.log("RolesAuthority owner:", rolesAuthority.owner());
        console2.log("RolesAuthority parent authority:", address(rolesAuthority.authority()));
    }
}
