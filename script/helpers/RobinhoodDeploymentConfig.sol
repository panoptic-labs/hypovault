// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HypoVault} from "../../src/HypoVault.sol";
import {HypoVaultFactory} from "../../src/HypoVaultFactory.sol";

/// @notice Immutable inputs for the production HypoVault architecture on Robinhood Chain.
library RobinhoodDeploymentConfig {
    uint256 internal constant CHAIN_ID = 4663;

    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 internal constant CREATE2_DEPLOYER_RUNTIME_CODE_HASH =
        0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989;
    address internal constant BROADCASTER = 0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8;

    bytes32 internal constant SALT =
        0xe78b3302c1a713353b49c40fcbd176c072797bfcd948b809b61bf8fd3216ea8b;

    address internal constant HYPO_VAULT_IMPLEMENTATION =
        0xF16714665955DBd0361D997eFc50fe391D96E8D0;
    address internal constant HYPO_VAULT_FACTORY = 0xd5049B2647de57141dE7F65E5124707B99A452A3;

    bytes32 internal constant HYPO_VAULT_INIT_CODE_HASH =
        0xa88995e4883d0fd6cf45327800243e559d18bd5f3ca22f39f5e83740f3817fcd;
    bytes32 internal constant HYPO_VAULT_FACTORY_INIT_CODE_HASH =
        0xccb4c113392d1b8e3e7fc51a6f09892ca6f018c418246d1664a6ccc82dea5dbb;

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

    function predictAddress(bytes32 initCodeHash) internal pure returns (address predicted) {
        predicted = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, SALT, initCodeHash))
                )
            )
        );
    }
}
