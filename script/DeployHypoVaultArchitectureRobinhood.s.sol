// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {RobinhoodDeploymentConfig as Config} from "./helpers/RobinhoodDeploymentConfig.sol";

/// @notice Deploys only the production HypoVault implementation and factory on Robinhood Chain.
/// @dev The canonical CREATE2 deployer expects calldata encoded as salt || initCode.
contract DeployHypoVaultArchitectureRobinhood is Script {
    error Create2DeploymentFailed(bytes revertData);
    error EmptyCreate2Deployer();
    error ExistingCode(address target);
    error InitCodeHashMismatch(bytes32 actual, bytes32 expected);
    error InvalidCreate2ReturnData(bytes returnData);
    error MissingDeployedCode(address target);
    error PredictedAddressMismatch(address actual, address expected);
    error ReferenceMismatch(address actual, address expected);
    error UnexpectedCreate2DeployerCodeHash(bytes32 actual, bytes32 expected);
    error UnexpectedChainId(uint256 actual, uint256 expected);

    function run() public {
        if (block.chainid != Config.CHAIN_ID) {
            revert UnexpectedChainId(block.chainid, Config.CHAIN_ID);
        }

        bytes memory implementationInitCode = Config.implementationInitCode();
        bytes memory factoryInitCode = Config.factoryInitCode();

        bytes32 implementationInitCodeHash = keccak256(implementationInitCode);
        bytes32 factoryInitCodeHash = keccak256(factoryInitCode);

        _assertHash(implementationInitCodeHash, Config.HYPO_VAULT_INIT_CODE_HASH);
        _assertHash(factoryInitCodeHash, Config.HYPO_VAULT_FACTORY_INIT_CODE_HASH);

        address predictedImplementation = Config.predictAddress(implementationInitCodeHash);
        address predictedFactory = Config.predictAddress(factoryInitCodeHash);

        _assertAddress(predictedImplementation, Config.HYPO_VAULT_IMPLEMENTATION);
        _assertAddress(predictedFactory, Config.HYPO_VAULT_FACTORY);

        console2.log("=== Robinhood HypoVault deterministic deployment ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("CREATE2 deployer:", Config.CREATE2_DEPLOYER);
        console2.log("Broadcast sender:", Config.BROADCASTER);
        console2.log("Broadcast sender balance:", Config.BROADCASTER.balance);
        console2.log("Recommended sender balance:", Config.RECOMMENDED_BROADCASTER_BALANCE);
        console2.log("CREATE2 salt:");
        console2.logBytes32(Config.SALT);
        console2.log("HypoVault init code hash:");
        console2.logBytes32(implementationInitCodeHash);
        console2.log("HypoVaultFactory init code hash:");
        console2.logBytes32(factoryInitCodeHash);
        console2.log("Predicted HypoVault implementation:", predictedImplementation);
        console2.log("Predicted HypoVaultFactory:", predictedFactory);

        _assertPreDeploymentState();

        vm.startBroadcast(Config.BROADCASTER);

        address implementation = _deploy(implementationInitCode);
        _assertAddress(implementation, Config.HYPO_VAULT_IMPLEMENTATION);
        if (implementation.code.length == 0) revert MissingDeployedCode(implementation);

        address factory = _deploy(factoryInitCode);
        _assertAddress(factory, Config.HYPO_VAULT_FACTORY);
        if (factory.code.length == 0) revert MissingDeployedCode(factory);

        vm.stopBroadcast();

        address hypoVaultReferenceAddress = HypoVaultFactory(factory).hypoVaultReference();
        if (hypoVaultReferenceAddress != Config.HYPO_VAULT_IMPLEMENTATION) {
            revert ReferenceMismatch(hypoVaultReferenceAddress, Config.HYPO_VAULT_IMPLEMENTATION);
        }

        console2.log("=== Deployment simulation complete ===");
        console2.log("HypoVault implementation:", implementation);
        console2.log("HypoVaultFactory:", factory);
        console2.log("HypoVaultFactory reference:", hypoVaultReferenceAddress);
    }

    function _assertPreDeploymentState() private view {
        if (Config.CREATE2_DEPLOYER.code.length == 0) revert EmptyCreate2Deployer();
        if (Config.CREATE2_DEPLOYER.codehash != Config.CREATE2_DEPLOYER_RUNTIME_CODE_HASH) {
            revert UnexpectedCreate2DeployerCodeHash(
                Config.CREATE2_DEPLOYER.codehash,
                Config.CREATE2_DEPLOYER_RUNTIME_CODE_HASH
            );
        }
        if (Config.HYPO_VAULT_IMPLEMENTATION.code.length != 0) {
            revert ExistingCode(Config.HYPO_VAULT_IMPLEMENTATION);
        }
        if (Config.HYPO_VAULT_FACTORY.code.length != 0) {
            revert ExistingCode(Config.HYPO_VAULT_FACTORY);
        }
    }

    function _deploy(bytes memory initCode) private returns (address deployed) {
        (bool success, bytes memory returnData) = Config.CREATE2_DEPLOYER.call(
            abi.encodePacked(Config.SALT, initCode)
        );
        if (!success) revert Create2DeploymentFailed(returnData);
        if (returnData.length != 20) revert InvalidCreate2ReturnData(returnData);

        assembly ("memory-safe") {
            deployed := shr(96, mload(add(returnData, 0x20)))
        }
    }

    function _assertHash(bytes32 actual, bytes32 expected) private pure {
        if (actual != expected) revert InitCodeHashMismatch(actual, expected);
    }

    function _assertAddress(address actual, address expected) private pure {
        if (actual != expected) revert PredictedAddressMismatch(actual, expected);
    }
}
