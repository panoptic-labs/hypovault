// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {RobinhoodDeploymentConfig as Config} from "./helpers/RobinhoodDeploymentConfig.sol";

/// @notice Read-only live verification for the Robinhood architecture deployment.
contract VerifyHypoVaultArchitectureRobinhood is Script {
    error MissingCode(address target);
    error ReferenceMismatch(address actual, address expected);
    error UnexpectedChainId(uint256 actual, uint256 expected);

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

        address hypoVaultReferenceAddress = HypoVaultFactory(Config.HYPO_VAULT_FACTORY)
            .hypoVaultReference();
        if (hypoVaultReferenceAddress != Config.HYPO_VAULT_IMPLEMENTATION) {
            revert ReferenceMismatch(hypoVaultReferenceAddress, Config.HYPO_VAULT_IMPLEMENTATION);
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
    }
}
