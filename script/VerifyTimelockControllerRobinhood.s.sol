// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {TimelockController} from "../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {RobinhoodDeploymentConfig as Config} from "./helpers/RobinhoodDeploymentConfig.sol";

/// @notice Read-only live verification for the Robinhood TimelockController deployment.
contract VerifyTimelockControllerRobinhood is Script {
    error MissingCode(address target);
    error TimelockConfigurationMismatch();
    error UnexpectedChainId(uint256 actual, uint256 expected);

    function run() public view {
        if (block.chainid != Config.CHAIN_ID) {
            revert UnexpectedChainId(block.chainid, Config.CHAIN_ID);
        }
        if (Config.TIMELOCK.code.length == 0) revert MissingCode(Config.TIMELOCK);

        TimelockController timelock = TimelockController(payable(Config.TIMELOCK));
        bool valid = timelock.getMinDelay() == Config.TIMELOCK_MIN_DELAY &&
            timelock.hasRole(timelock.PROPOSER_ROLE(), Config.TIMELOCK_PROPOSER_SAFE) &&
            timelock.hasRole(timelock.CANCELLER_ROLE(), Config.TIMELOCK_PROPOSER_SAFE) &&
            timelock.hasRole(timelock.EXECUTOR_ROLE(), Config.TIMELOCK_EXECUTOR) &&
            timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), Config.TIMELOCK) &&
            !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), Config.BROADCASTER);
        if (!valid) revert TimelockConfigurationMismatch();

        console2.log("=== Robinhood TimelockController live verification ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("TimelockController:", Config.TIMELOCK);
        console2.log("TimelockController code hash:");
        console2.logBytes32(Config.TIMELOCK.codehash);
        console2.log("Minimum delay:", timelock.getMinDelay());
        console2.log("Proposer/Canceller Safe:", Config.TIMELOCK_PROPOSER_SAFE);
        console2.log("Open execution:", true);
        console2.log("Self-administered:", true);
    }
}
