// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HypoVault} from "../../src/HypoVault.sol";
import {HypoVaultFactory} from "../../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../../src/accountants/PanopticVaultAccountant.sol";
import {CollateralTrackerDecoderAndSanitizer} from "../../src/DecodersAndSanitizers/CollateralTrackerDecoderAndSanitizer.sol";
import {RolesAuthority, Authority} from "../../lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {TimelockController} from "../../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

/// @notice Immutable inputs for the production HypoVault architecture on Robinhood Chain.
library RobinhoodDeploymentConfig {
    uint256 internal constant CHAIN_ID = 4663;

    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 internal constant CREATE2_DEPLOYER_RUNTIME_CODE_HASH =
        0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989;
    address internal constant BROADCASTER = 0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    // keccak256(bytes("my-salt-v1")); kept literal as the production source of truth.
    bytes32 internal constant PRODUCTION_SALT =
        0xe78b3302c1a713353b49c40fcbd176c072797bfcd948b809b61bf8fd3216ea8b;

    // These inputs exactly reproduce the Ethereum production timelock deployment.
    bytes32 internal constant TIMELOCK_SALT =
        0x5894bdfe5513cb18dd7f6e5ae30cd1bbcf26773ae48d25d0d72c472384825707;
    uint256 internal constant TIMELOCK_MIN_DELAY = 1 days;
    uint256 internal constant TIMELOCK_MAX_DELAY = 7 days;
    address internal constant TIMELOCK_PROPOSER_SAFE = 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1;
    uint256 internal constant TIMELOCK_PROPOSER_SAFE_THRESHOLD = 3;
    address internal constant TIMELOCK_EXECUTOR = address(0);
    address internal constant TIMELOCK_ADMIN = address(0);

    address internal constant HYPO_VAULT_IMPLEMENTATION =
        0xF16714665955DBd0361D997eFc50fe391D96E8D0;
    address internal constant HYPO_VAULT_FACTORY = 0xd5049B2647de57141dE7F65E5124707B99A452A3;
    address internal constant ACCOUNTANT = 0x9e345d862c41010F87D8E5A279e8D320D2831D36;
    address internal constant DECODER = 0xC87c45d2dbE5acb56013e2591427ECC84Fa251E6;
    address internal constant ROLES_AUTHORITY = 0xb952D345c413Ddb7850173422bAe4968e0330598;
    address internal constant TIMELOCK = 0xaeB1ad4d0452fd79eD7dDE25A08Fd60346c60912;

    bytes32 internal constant HYPO_VAULT_INIT_CODE_HASH =
        0xa88995e4883d0fd6cf45327800243e559d18bd5f3ca22f39f5e83740f3817fcd;
    bytes32 internal constant HYPO_VAULT_FACTORY_INIT_CODE_HASH =
        0xccb4c113392d1b8e3e7fc51a6f09892ca6f018c418246d1664a6ccc82dea5dbb;
    bytes32 internal constant ACCOUNTANT_INIT_CODE_HASH =
        0x262c34d6f6608ff7919f6941c8f797342d2d2288e180c9495f38d02c0384de95;
    bytes32 internal constant DECODER_INIT_CODE_HASH =
        0x62c4eeca8b5ece9e90d5ac672675f7d5e2223aab5e0c4db9257d5a6975230503;
    bytes32 internal constant ROLES_AUTHORITY_INIT_CODE_HASH =
        0x6bc9405e6dae7f22395cff352cca6063d4fa4e0e25e4557d3ee4dd53d0226b33;
    bytes32 internal constant TIMELOCK_INIT_CODE_HASH =
        0xe2b9422b27a33697d9c1f32e55fd0e96817d67f969ec8214b9646a2717d33e7e;

    uint256 internal constant RECOMMENDED_BROADCASTER_BALANCE = 0.01 ether;

    function implementationInitCode() internal pure returns (bytes memory) {
        return type(HypoVault).creationCode;
    }

    function factoryInitCode() internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(HypoVaultFactory).creationCode,
                abi.encode(HYPO_VAULT_IMPLEMENTATION)
            );
    }

    function accountantInitCode() internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(PanopticVaultAccountant).creationCode,
                abi.encode(BROADCASTER, WETH)
            );
    }

    function decoderInitCode() internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(CollateralTrackerDecoderAndSanitizer).creationCode,
                abi.encode(HYPO_VAULT_IMPLEMENTATION)
            );
    }

    function rolesAuthorityInitCode() internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(RolesAuthority).creationCode,
                abi.encode(BROADCASTER, Authority(address(0)))
            );
    }

    function timelockInitCode() internal pure returns (bytes memory) {
        address[] memory proposers = new address[](1);
        proposers[0] = TIMELOCK_PROPOSER_SAFE;

        address[] memory executors = new address[](1);
        executors[0] = TIMELOCK_EXECUTOR;

        return
            abi.encodePacked(
                type(TimelockController).creationCode,
                abi.encode(TIMELOCK_MIN_DELAY, proposers, executors, TIMELOCK_ADMIN)
            );
    }

    function predictAddress(bytes32 initCodeHash) internal pure returns (address predicted) {
        return predictAddress(PRODUCTION_SALT, initCodeHash);
    }

    function predictAddress(
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address predicted) {
        predicted = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, initCodeHash))
                )
            )
        );
    }
}
