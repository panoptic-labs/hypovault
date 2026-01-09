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
    address constant FACTORY_ADDRESS = address(0xebb431ca19A7B245A0827BFA08b5167694B75F38);
    address constant ACCOUNTANT_ADDRESS = address(0x529e41f74221963D43B0b4466674EA24A19F1c27);
    address constant DECODER_ADDRESS = address(0x045AB155Ee70f57fc1672f100FE4939a0d052731);
    address constant AUTHORITY_ADDRESS = address(0xa1FC02EEeDb96F9C0231234DB2824c1FfFeD60CD);
    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0x0A9a8e10e6D9601b1eE056D194c77D5a2dE40F77);

    address constant VAULT_TURNKEY_ADDRESS = address(0x3c1c79d0cfc316Ba959194c89696a8382d7d283b);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-usdc"));

    // Sepolia USDC address
    IERC20Partial sepoliaUsdc = IERC20Partial(0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A);

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;

        console.log("=== Deploying USDC Vault ===");
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
            "povLendUSDC",
            "Panoptic Lend Vault | USDC",
            salt
        );
        vm.stopBroadcast();
    }
}
