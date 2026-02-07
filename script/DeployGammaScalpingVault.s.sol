// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployUSDCVault is Script, DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0x5d24AeA981D6e5F38A21Cfe5b81204D2F6225271);
    address constant ACCOUNTANT_ADDRESS = address(0x6100455aA6637093464E75a9Cb9785F7A8D51E80);
    address constant DECODER_ADDRESS = address(0x8Cf3d6d7C2E6718e36b9686385c384e5002Db7e1);
    address constant AUTHORITY_ADDRESS = address(0x9166293A301CcC805d5171A2D1e62050ba72795D);
    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0x244Bf88435Be52e8dFb642a718ef4b6d0A1166BF);

    address constant VAULT_TURNKEY_ADDRESS = address(0x421297FB967aBb21fF6FCd7b66589De857a4F4cc);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-gamma-scalping"));

    // Sepolia USDC address
    IERC20Partial sepoliaUsdc = IERC20Partial(0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A);

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;

        console.log("=== Deploying Gamma Scalping USDC Vault ===");
        console.log("Deployer:", deployer);
        console.log("Using Factory:", FACTORY_ADDRESS);
        console.log("Using Accountant:", ACCOUNTANT_ADDRESS);
        console.log("Using Decoder:", DECODER_ADDRESS);
        console.log("Using Authority:", AUTHORITY_ADDRESS);

        deployVault(
            deployer,
            FACTORY_ADDRESS,
            ACCOUNTANT_ADDRESS,
            DECODER_ADDRESS,
            AUTHORITY_ADDRESS,
            VAULT_TURNKEY_ADDRESS,
            address(sepoliaUsdc),
            COLLATERAL_TRACKER_ADDRESS,
            "gammaScalpingUSDC",
            "Panoptic Gamma Scalping Vault | USDC",
            salt
        );
        vm.stopBroadcast();
    }
}
