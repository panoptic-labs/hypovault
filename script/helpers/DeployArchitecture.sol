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
        address deployer,
        address wethAddress
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
        hypoVaultImpl = address(new HypoVault{salt: salt}());
        console.log("=== CREATE2 Deployment Info ===");
        console.log("HypoVault implementation Address:", hypoVaultImpl);

        // 2. Deploy HypoVaultFactory with CREATE2
        vaultFactory = address(new HypoVaultFactory{salt: salt}(hypoVaultImpl));
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Factory Address:", vaultFactory);

        // 3. Deploy new Accountant with CREATE2
        accountant = address(new PanopticVaultAccountant{salt: salt}(
            deployer,
            wethAddress
        ));
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Accountant Address:", accountant);

        // 4. Deploy CollateralTrackerDecoderAndSanitizer with CREATE2
        collateralTrackerDecoderAndSanitizer = address(new CollateralTrackerDecoderAndSanitizer{
            salt: salt
        }(hypoVaultImpl));
        console.log("=== CREATE2 Deployment Info ===");
        console.log(
            "CollateralTrackerDecoderAndSanitizer Address:",
            collateralTrackerDecoderAndSanitizer
        );

        // 5. Deploy and configure RolesAuthority with CREATE2
        rolesAuthority = address(new RolesAuthority{salt: salt}(deployer, Authority(address(0))));
        console.log("=== CREATE2 Deployment Info ===");
        console.log("RolesAuthority Address:", rolesAuthority);
    }
}
