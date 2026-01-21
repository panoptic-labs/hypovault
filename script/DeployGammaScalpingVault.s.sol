// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployGammaScalpingVault is Script, DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0xebb431ca19A7B245A0827BFA08b5167694B75F38);
    address constant ACCOUNTANT_ADDRESS = address(0x529e41f74221963D43B0b4466674EA24A19F1c27);
    address constant DECODER_ADDRESS = address(0x045AB155Ee70f57fc1672f100FE4939a0d052731);
    address constant AUTHORITY_ADDRESS = address(0xa1FC02EEeDb96F9C0231234DB2824c1FfFeD60CD);
    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0xFA04A834767C4ec40904EfD31a14353b7746aaC1);

    address constant VAULT_TURNKEY_ADDRESS = address(0x421297FB967aBb21fF6FCd7b66589De857a4F4cc); // Turnkey3

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-gamma-usdc"));

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
            "gammaUSDC",
            "Panoptic Gamma Scalping Vault | USDC",
            salt
        );
        vm.stopBroadcast();
    }
}
