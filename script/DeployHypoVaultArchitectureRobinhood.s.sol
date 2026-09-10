// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {RolesAuthority} from "../lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {RobinhoodDeploymentConfig as Config} from "./helpers/RobinhoodDeploymentConfig.sol";

/// @notice Deploys the five-contract production HypoVault architecture on Robinhood Chain.
/// @dev The canonical CREATE2 deployer expects calldata encoded as salt || initCode.
contract DeployHypoVaultArchitectureRobinhood is Script {
    error Create2DeploymentFailed(bytes revertData);
    error EmptyCreate2Deployer();
    error EmptyWeth();
    error AuthorityMismatch(address actual, address expected);
    error InitCodeHashMismatch(bytes32 actual, bytes32 expected);
    error InvalidCreate2ReturnData(bytes returnData);
    error MissingDeployedCode(address target);
    error OwnerMismatch(address actual, address expected);
    error PredictedAddressMismatch(address actual, address expected);
    error ReferenceMismatch(address actual, address expected);
    error UnexpectedCreate2DeployerCodeHash(bytes32 actual, bytes32 expected);
    error UnexpectedRuntimeCodeHash(address target, bytes32 actual, bytes32 expected);
    error UnexpectedChainId(uint256 actual, uint256 expected);
    error WethMismatch(address actual, address expected);

    function run() public {
        if (block.chainid != Config.CHAIN_ID) {
            revert UnexpectedChainId(block.chainid, Config.CHAIN_ID);
        }

        console2.log("=== Robinhood HypoVault deterministic deployment ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("CREATE2 deployer:", Config.CREATE2_DEPLOYER);
        console2.log("Broadcast sender:", Config.BROADCASTER);
        console2.log("Broadcast sender balance:", Config.BROADCASTER.balance);
        console2.log("Recommended sender balance:", Config.RECOMMENDED_BROADCASTER_BALANCE);
        console2.log("CREATE2 salt:");
        console2.logBytes32(Config.PRODUCTION_SALT);
        _assertAndPrintDeploymentInputs();

        _assertPreDeploymentState();

        vm.startBroadcast(Config.BROADCASTER);

        address implementation = _deployIfMissing(
            "HypoVault implementation",
            Config.implementationInitCode(),
            Config.HYPO_VAULT_IMPLEMENTATION,
            Config.HYPO_VAULT_RUNTIME_CODE_HASH
        );
        address factory = _deployIfMissing(
            "HypoVaultFactory",
            Config.factoryInitCode(),
            Config.HYPO_VAULT_FACTORY,
            Config.HYPO_VAULT_FACTORY_RUNTIME_CODE_HASH
        );
        address accountant = _deployIfMissing(
            "PanopticVaultAccountant",
            Config.accountantInitCode(),
            Config.ACCOUNTANT,
            Config.ACCOUNTANT_RUNTIME_CODE_HASH
        );
        address decoder = _deployIfMissing(
            "CollateralTrackerDecoderAndSanitizer",
            Config.decoderInitCode(),
            Config.DECODER,
            Config.DECODER_RUNTIME_CODE_HASH
        );
        address rolesAuthority = _deployIfMissing(
            "RolesAuthority",
            Config.rolesAuthorityInitCode(),
            Config.ROLES_AUTHORITY,
            Config.ROLES_AUTHORITY_RUNTIME_CODE_HASH
        );

        vm.stopBroadcast();

        _assertPostDeploymentState();

        console2.log("=== Deployment simulation complete ===");
        console2.log("HypoVault implementation:", implementation);
        console2.log("HypoVaultFactory:", factory);
        console2.log("PanopticVaultAccountant:", accountant);
        console2.log("CollateralTrackerDecoderAndSanitizer:", decoder);
        console2.log("RolesAuthority:", rolesAuthority);
        console2.log("Initial accountant/authority owner:", Config.BROADCASTER);
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
        if (Config.WETH.code.length == 0) revert EmptyWeth();

        _assertExistingDeploymentState();
    }

    function _assertExistingDeploymentState() private view {
        _assertCodeIfPresent(Config.HYPO_VAULT_IMPLEMENTATION, Config.HYPO_VAULT_RUNTIME_CODE_HASH);
        _assertCodeIfPresent(
            Config.HYPO_VAULT_FACTORY,
            Config.HYPO_VAULT_FACTORY_RUNTIME_CODE_HASH
        );
        _assertCodeIfPresent(Config.ACCOUNTANT, Config.ACCOUNTANT_RUNTIME_CODE_HASH);
        _assertCodeIfPresent(Config.DECODER, Config.DECODER_RUNTIME_CODE_HASH);
        _assertCodeIfPresent(Config.ROLES_AUTHORITY, Config.ROLES_AUTHORITY_RUNTIME_CODE_HASH);

        if (Config.HYPO_VAULT_FACTORY.code.length != 0) {
            _assertFactoryState();
        }
        if (Config.ACCOUNTANT.code.length != 0) {
            _assertAccountantState();
        }
        if (Config.ROLES_AUTHORITY.code.length != 0) {
            _assertRolesAuthorityState();
        }
    }

    function _assertAndPrintDeploymentInputs() private pure {
        _assertAndPrintDeploymentInput(
            "HypoVault implementation",
            Config.implementationInitCode(),
            Config.HYPO_VAULT_INIT_CODE_HASH,
            Config.HYPO_VAULT_IMPLEMENTATION
        );
        _assertAndPrintDeploymentInput(
            "HypoVaultFactory",
            Config.factoryInitCode(),
            Config.HYPO_VAULT_FACTORY_INIT_CODE_HASH,
            Config.HYPO_VAULT_FACTORY
        );
        _assertAndPrintDeploymentInput(
            "PanopticVaultAccountant",
            Config.accountantInitCode(),
            Config.ACCOUNTANT_INIT_CODE_HASH,
            Config.ACCOUNTANT
        );
        _assertAndPrintDeploymentInput(
            "CollateralTrackerDecoderAndSanitizer",
            Config.decoderInitCode(),
            Config.DECODER_INIT_CODE_HASH,
            Config.DECODER
        );
        _assertAndPrintDeploymentInput(
            "RolesAuthority",
            Config.rolesAuthorityInitCode(),
            Config.ROLES_AUTHORITY_INIT_CODE_HASH,
            Config.ROLES_AUTHORITY
        );
    }

    function _assertAndPrintDeploymentInput(
        string memory label,
        bytes memory initCode,
        bytes32 expectedHash,
        address expectedAddress
    ) private pure {
        bytes32 initCodeHash = keccak256(initCode);
        _assertHash(initCodeHash, expectedHash);

        address predicted = Config.predictAddress(initCodeHash);
        _assertAddress(predicted, expectedAddress);

        console2.log(string.concat(label, " init code hash:"));
        console2.logBytes32(initCodeHash);
        console2.log(string.concat("Predicted ", label, ":"), predicted);
    }

    function _assertPostDeploymentState() private view {
        _assertRequiredCode(Config.HYPO_VAULT_IMPLEMENTATION, Config.HYPO_VAULT_RUNTIME_CODE_HASH);
        _assertRequiredCode(Config.HYPO_VAULT_FACTORY, Config.HYPO_VAULT_FACTORY_RUNTIME_CODE_HASH);
        _assertRequiredCode(Config.ACCOUNTANT, Config.ACCOUNTANT_RUNTIME_CODE_HASH);
        _assertRequiredCode(Config.DECODER, Config.DECODER_RUNTIME_CODE_HASH);
        _assertRequiredCode(Config.ROLES_AUTHORITY, Config.ROLES_AUTHORITY_RUNTIME_CODE_HASH);
        _assertFactoryState();
        _assertAccountantState();
        _assertRolesAuthorityState();
    }

    function _assertFactoryState() private view {
        address hypoVaultReferenceAddress = HypoVaultFactory(Config.HYPO_VAULT_FACTORY)
            .hypoVaultReference();
        if (hypoVaultReferenceAddress != Config.HYPO_VAULT_IMPLEMENTATION) {
            revert ReferenceMismatch(hypoVaultReferenceAddress, Config.HYPO_VAULT_IMPLEMENTATION);
        }
    }

    function _assertAccountantState() private view {
        PanopticVaultAccountant accountantContract = PanopticVaultAccountant(Config.ACCOUNTANT);
        if (accountantContract.owner() != Config.BROADCASTER) {
            revert OwnerMismatch(accountantContract.owner(), Config.BROADCASTER);
        }
        if (accountantContract.wethAddress() != Config.WETH) {
            revert WethMismatch(accountantContract.wethAddress(), Config.WETH);
        }
    }

    function _assertRolesAuthorityState() private view {
        RolesAuthority rolesAuthorityContract = RolesAuthority(Config.ROLES_AUTHORITY);
        if (rolesAuthorityContract.owner() != Config.BROADCASTER) {
            revert OwnerMismatch(rolesAuthorityContract.owner(), Config.BROADCASTER);
        }
        if (address(rolesAuthorityContract.authority()) != address(0)) {
            revert AuthorityMismatch(address(rolesAuthorityContract.authority()), address(0));
        }
    }

    function _deployIfMissing(
        string memory label,
        bytes memory initCode,
        address expectedAddress,
        bytes32 expectedRuntimeCodeHash
    ) internal returns (address deployed) {
        if (expectedAddress.code.length != 0) {
            _assertCodeIfPresent(expectedAddress, expectedRuntimeCodeHash);
            console2.log(string.concat("Skipping existing ", label, ":"), expectedAddress);
            return expectedAddress;
        }

        deployed = _deploy(initCode);
        _assertAddress(deployed, expectedAddress);
        _assertRequiredCode(deployed, expectedRuntimeCodeHash);
    }

    function _assertCodeIfPresent(address target, bytes32 expectedCodeHash) private view {
        if (target.code.length != 0 && target.codehash != expectedCodeHash) {
            revert UnexpectedRuntimeCodeHash(target, target.codehash, expectedCodeHash);
        }
    }

    function _assertRequiredCode(address target, bytes32 expectedCodeHash) private view {
        if (target.code.length == 0) revert MissingDeployedCode(target);
        if (target.codehash != expectedCodeHash) {
            revert UnexpectedRuntimeCodeHash(target, target.codehash, expectedCodeHash);
        }
    }

    function _deploy(bytes memory initCode) private returns (address deployed) {
        (bool success, bytes memory returnData) = Config.CREATE2_DEPLOYER.call(
            abi.encodePacked(Config.PRODUCTION_SALT, initCode)
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
