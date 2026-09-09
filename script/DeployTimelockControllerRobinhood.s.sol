// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {TimelockController} from "../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {RobinhoodDeploymentConfig as Config} from "./helpers/RobinhoodDeploymentConfig.sol";

interface ISafeThreshold {
    function getThreshold() external view returns (uint256);
}

/// @notice Deploys the production TimelockController on Robinhood Chain.
/// @dev This deliberately does not transfer ownership of any contract.
contract DeployTimelockControllerRobinhood is Script {
    error Create2DeploymentFailed(bytes revertData);
    error EmptyCreate2Deployer();
    error EmptyProposerSafe();
    error ExistingCode(address target);
    error InitCodeHashMismatch(bytes32 actual, bytes32 expected);
    error InvalidCreate2ReturnData(bytes returnData);
    error InvalidTimelockDelay(uint256 actual, uint256 maximum);
    error MissingDeployedCode(address target);
    error PredictedAddressMismatch(address actual, address expected);
    error ProposerSafeThresholdMismatch(uint256 actual, uint256 expected);
    error TimelockConfigurationMismatch();
    error UnexpectedChainId(uint256 actual, uint256 expected);
    error UnexpectedCreate2DeployerCodeHash(bytes32 actual, bytes32 expected);

    function run() public {
        if (block.chainid != Config.CHAIN_ID) {
            revert UnexpectedChainId(block.chainid, Config.CHAIN_ID);
        }
        if (Config.TIMELOCK_MIN_DELAY > Config.TIMELOCK_MAX_DELAY) {
            revert InvalidTimelockDelay(Config.TIMELOCK_MIN_DELAY, Config.TIMELOCK_MAX_DELAY);
        }

        bytes memory initCode = Config.timelockInitCode();
        bytes32 initCodeHash = keccak256(initCode);
        if (initCodeHash != Config.TIMELOCK_INIT_CODE_HASH) {
            revert InitCodeHashMismatch(initCodeHash, Config.TIMELOCK_INIT_CODE_HASH);
        }

        address predicted = Config.predictAddress(Config.TIMELOCK_SALT, initCodeHash);
        if (predicted != Config.TIMELOCK) {
            revert PredictedAddressMismatch(predicted, Config.TIMELOCK);
        }

        console2.log("=== Robinhood TimelockController deterministic deployment ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("CREATE2 deployer:", Config.CREATE2_DEPLOYER);
        console2.log("Broadcast sender:", Config.BROADCASTER);
        console2.log("Broadcast sender balance:", Config.BROADCASTER.balance);
        console2.log("CREATE2 salt:");
        console2.logBytes32(Config.TIMELOCK_SALT);
        console2.log("Timelock init code hash:");
        console2.logBytes32(initCodeHash);
        console2.log("Predicted TimelockController:", predicted);
        console2.log("Minimum delay:", Config.TIMELOCK_MIN_DELAY);
        console2.log("Proposer/Canceller Safe:", Config.TIMELOCK_PROPOSER_SAFE);
        console2.log("Executor (zero means open execution):", Config.TIMELOCK_EXECUTOR);
        console2.log("Admin (zero means self-administered):", Config.TIMELOCK_ADMIN);

        _assertPreDeploymentState();

        vm.startBroadcast(Config.BROADCASTER);
        address deployed = _deploy(initCode);
        vm.stopBroadcast();

        if (deployed != Config.TIMELOCK) {
            revert PredictedAddressMismatch(deployed, Config.TIMELOCK);
        }
        if (deployed.code.length == 0) revert MissingDeployedCode(deployed);
        _assertTimelockConfiguration(TimelockController(payable(deployed)));

        console2.log("=== Deployment simulation complete ===");
        console2.log("TimelockController:", deployed);
        console2.log("No ownership transfers were performed.");
    }

    function _assertPreDeploymentState() private view {
        if (Config.CREATE2_DEPLOYER.code.length == 0) revert EmptyCreate2Deployer();
        if (Config.CREATE2_DEPLOYER.codehash != Config.CREATE2_DEPLOYER_RUNTIME_CODE_HASH) {
            revert UnexpectedCreate2DeployerCodeHash(
                Config.CREATE2_DEPLOYER.codehash,
                Config.CREATE2_DEPLOYER_RUNTIME_CODE_HASH
            );
        }
        if (Config.TIMELOCK.code.length != 0) revert ExistingCode(Config.TIMELOCK);
        if (Config.TIMELOCK_PROPOSER_SAFE.code.length == 0) revert EmptyProposerSafe();

        uint256 threshold = ISafeThreshold(Config.TIMELOCK_PROPOSER_SAFE).getThreshold();
        if (threshold != Config.TIMELOCK_PROPOSER_SAFE_THRESHOLD) {
            revert ProposerSafeThresholdMismatch(
                threshold,
                Config.TIMELOCK_PROPOSER_SAFE_THRESHOLD
            );
        }
    }

    function _deploy(bytes memory initCode) private returns (address deployed) {
        (bool success, bytes memory returnData) = Config.CREATE2_DEPLOYER.call(
            abi.encodePacked(Config.TIMELOCK_SALT, initCode)
        );
        if (!success) revert Create2DeploymentFailed(returnData);
        if (returnData.length != 20) revert InvalidCreate2ReturnData(returnData);

        assembly ("memory-safe") {
            deployed := shr(96, mload(add(returnData, 0x20)))
        }
    }

    function _assertTimelockConfiguration(TimelockController timelock) private view {
        bool valid = timelock.getMinDelay() == Config.TIMELOCK_MIN_DELAY &&
            timelock.hasRole(timelock.PROPOSER_ROLE(), Config.TIMELOCK_PROPOSER_SAFE) &&
            timelock.hasRole(timelock.CANCELLER_ROLE(), Config.TIMELOCK_PROPOSER_SAFE) &&
            timelock.hasRole(timelock.EXECUTOR_ROLE(), Config.TIMELOCK_EXECUTOR) &&
            timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)) &&
            !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), Config.BROADCASTER);
        if (!valid) revert TimelockConfigurationMismatch();
    }
}
