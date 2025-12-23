// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {HypoVault} from "../../src/HypoVault.sol";
import {HypoVaultFactory} from "../../src/HypoVaultFactory.sol";
import "../../src/accountants/PanopticVaultAccountant.sol";
import {CollateralTrackerDecoderAndSanitizer} from "../../src/DecodersAndSanitizers/CollateralTrackerDecoderAndSanitizer.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";

contract DeployArchitecture {
    function deployArchitecture(
        bytes32 salt,
        address deployer
    )
        internal
        returns (
            address hypoVaultImpl,
            address vaultFactory,
            address accountant,
            address collateralTrackerDecoderAndSanitizer,
            address rolesAuthority
        )
    {
        console.log("=== Deployer Address ===");
        console.log("Deployer:", deployer);

        // 1. Deploy reference HypoVault implementation with CREATE2
        HypoVault hypoVaultImpl = new HypoVault{salt: salt}();
        address hypoVaultImplAddress = address(hypoVaultImpl);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("HypoVault implementation Address:", hypoVaultImplAddress);

        // 2. Deploy HypoVaultFactory with CREATE2
        HypoVaultFactory vaultFactory = new HypoVaultFactory{salt: salt}(hypoVaultImplAddress);
        address vaultFactoryAddress = address(vaultFactory);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Factory Address:", vaultFactoryAddress);

        // 3. Deploy new Accountant with CREATE2
        PanopticVaultAccountant accountant = new PanopticVaultAccountant{salt: salt}(deployer);
        address accountantAddress = address(accountant);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Accountant Address:", accountantAddress);

        // 4. Deploy CollateralTrackerDecoderAndSanitizer with CREATE2
        CollateralTrackerDecoderAndSanitizer decoder = new CollateralTrackerDecoderAndSanitizer{
            salt: salt
        }(hypoVaultImplAddress);
        address collateralTrackerDecoderAndSanitizerAddress = address(decoder);
        console.log("=== CREATE2 Deployment Info ===");
        console.log(
            "CollateralTrackerDecoderAndSanitizer Address:",
            collateralTrackerDecoderAndSanitizerAddress
        );

        // 5. Deploy and configure RolesAuthority with CREATE2
        RolesAuthority authority = new RolesAuthority{salt: salt}(deployer, Authority(address(0)));
        address authorityAddress = address(authority);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("RolesAuthority Address:", authorityAddress);

        return (
            hypoVaultImplAddress,
            vaultFactoryAddress,
            accountantAddress,
            collateralTrackerDecoderAndSanitizerAddress,
            authorityAddress
        );
    }
}
