// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {HypoVaultFactory} from "../../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../../src/accountants/PanopticVaultAccountant.sol";
import {RolesAuthority} from "../../lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {RobinhoodDeploymentConfig as Config} from "../../script/helpers/RobinhoodDeploymentConfig.sol";
import {TimelockController} from "../../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract RobinhoodDeterministicDeploymentTest is Test {
    bytes internal constant CREATE2_DEPLOYER_RUNTIME =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
    bytes32 internal constant VAULT_CREATED_TOPIC =
        keccak256("VaultCreated(address,address,address,address,uint256,string,string)");

    function testProductionInitCodeHashes() public pure {
        assertEq(keccak256(CREATE2_DEPLOYER_RUNTIME), Config.CREATE2_DEPLOYER_RUNTIME_CODE_HASH);
        assertEq(Config.PRODUCTION_SALT, keccak256("my-salt-v1"));
        assertEq(Config.TIMELOCK_SALT, keccak256("hypovault-timelock-v1"));
        assertEq(keccak256(Config.implementationInitCode()), Config.HYPO_VAULT_INIT_CODE_HASH);
        assertEq(keccak256(Config.factoryInitCode()), Config.HYPO_VAULT_FACTORY_INIT_CODE_HASH);
        assertEq(keccak256(Config.accountantInitCode()), Config.ACCOUNTANT_INIT_CODE_HASH);
        assertEq(keccak256(Config.decoderInitCode()), Config.DECODER_INIT_CODE_HASH);
        assertEq(keccak256(Config.rolesAuthorityInitCode()), Config.ROLES_AUTHORITY_INIT_CODE_HASH);
        assertEq(keccak256(Config.timelockInitCode()), Config.TIMELOCK_INIT_CODE_HASH);
    }

    function testProductionPredictedAddresses() public pure {
        assertEq(
            Config.predictAddress(Config.HYPO_VAULT_INIT_CODE_HASH),
            Config.HYPO_VAULT_IMPLEMENTATION
        );
        assertEq(
            Config.predictAddress(Config.HYPO_VAULT_FACTORY_INIT_CODE_HASH),
            Config.HYPO_VAULT_FACTORY
        );
        assertEq(Config.predictAddress(Config.ACCOUNTANT_INIT_CODE_HASH), Config.ACCOUNTANT);
        assertEq(Config.predictAddress(Config.DECODER_INIT_CODE_HASH), Config.DECODER);
        assertEq(
            Config.predictAddress(Config.ROLES_AUTHORITY_INIT_CODE_HASH),
            Config.ROLES_AUTHORITY
        );
        assertEq(
            Config.predictAddress(Config.TIMELOCK_SALT, Config.TIMELOCK_INIT_CODE_HASH),
            Config.TIMELOCK
        );
    }

    function testFactoryConstructorArgument() public pure {
        bytes memory initCode = Config.factoryInitCode();
        uint256 creationCodeLength = type(HypoVaultFactory).creationCode.length;
        bytes32 encodedReference;

        assembly ("memory-safe") {
            encodedReference := mload(add(add(initCode, 0x20), creationCodeLength))
        }

        assertEq(address(uint160(uint256(encodedReference))), Config.HYPO_VAULT_IMPLEMENTATION);
    }

    function testCanonicalDeployerDeploysProductionArchitecture() public {
        vm.etch(Config.CREATE2_DEPLOYER, CREATE2_DEPLOYER_RUNTIME);

        address implementation = _deploy(Config.implementationInitCode());
        assertEq(implementation, Config.HYPO_VAULT_IMPLEMENTATION);
        assertGt(implementation.code.length, 0);

        address factory = _deploy(Config.factoryInitCode());
        assertEq(factory, Config.HYPO_VAULT_FACTORY);
        assertGt(factory.code.length, 0);
        assertEq(HypoVaultFactory(factory).hypoVaultReference(), Config.HYPO_VAULT_IMPLEMENTATION);

        address accountantAddress = _deploy(Config.accountantInitCode());
        assertEq(accountantAddress, Config.ACCOUNTANT);
        PanopticVaultAccountant accountant = PanopticVaultAccountant(accountantAddress);
        assertEq(accountant.owner(), Config.BROADCASTER);
        assertEq(accountant.wethAddress(), Config.WETH);

        address decoder = _deploy(Config.decoderInitCode());
        assertEq(decoder, Config.DECODER);
        assertGt(decoder.code.length, 0);

        address rolesAuthorityAddress = _deploy(Config.rolesAuthorityInitCode());
        assertEq(rolesAuthorityAddress, Config.ROLES_AUTHORITY);
        RolesAuthority rolesAuthority = RolesAuthority(rolesAuthorityAddress);
        assertEq(rolesAuthority.owner(), Config.BROADCASTER);
        assertEq(address(rolesAuthority.authority()), address(0));
    }

    function testLegacySaltDoesNotProduceProductionAddresses() public pure {
        bytes32 legacySalt = keccak256("my-salt-v0");

        assertNotEq(
            _predictWithSalt(Config.HYPO_VAULT_INIT_CODE_HASH, legacySalt),
            Config.HYPO_VAULT_IMPLEMENTATION
        );
        assertNotEq(
            _predictWithSalt(Config.HYPO_VAULT_FACTORY_INIT_CODE_HASH, legacySalt),
            Config.HYPO_VAULT_FACTORY
        );
    }

    function testCanonicalDeployerDeploysProductionTimelock() public {
        vm.etch(Config.CREATE2_DEPLOYER, CREATE2_DEPLOYER_RUNTIME);

        address timelockAddress = _deploy(Config.TIMELOCK_SALT, Config.timelockInitCode());
        assertEq(timelockAddress, Config.TIMELOCK);
        assertGt(timelockAddress.code.length, 0);

        TimelockController timelock = TimelockController(payable(timelockAddress));
        assertEq(timelock.getMinDelay(), Config.TIMELOCK_MIN_DELAY);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), Config.TIMELOCK_PROPOSER_SAFE));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), Config.TIMELOCK_PROPOSER_SAFE));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), Config.TIMELOCK_EXECUTOR));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), timelockAddress));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), Config.BROADCASTER));
    }

    function testNoVaultInstanceIsCreatedByArchitectureDeployment() public {
        vm.recordLogs();
        vm.etch(Config.CREATE2_DEPLOYER, CREATE2_DEPLOYER_RUNTIME);

        _deploy(Config.implementationInitCode());
        _deploy(Config.factoryInitCode());
        _deploy(Config.accountantInitCode());
        _deploy(Config.decoderInitCode());
        _deploy(Config.rolesAuthorityInitCode());

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics.length == 0 || logs[i].topics[0] != VAULT_CREATED_TOPIC);
        }
    }

    function _deploy(bytes memory initCode) private returns (address deployed) {
        return _deploy(Config.PRODUCTION_SALT, initCode);
    }

    function _deploy(bytes32 salt, bytes memory initCode) private returns (address deployed) {
        (bool success, bytes memory returnData) = Config.CREATE2_DEPLOYER.call(
            abi.encodePacked(salt, initCode)
        );

        assertTrue(success);
        assertEq(returnData.length, 20);

        assembly ("memory-safe") {
            deployed := shr(96, mload(add(returnData, 0x20)))
        }
    }

    function _predictWithSalt(bytes32 initCodeHash, bytes32 salt) private pure returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                Config.CREATE2_DEPLOYER,
                                salt,
                                initCodeHash
                            )
                        )
                    )
                )
            );
    }
}
