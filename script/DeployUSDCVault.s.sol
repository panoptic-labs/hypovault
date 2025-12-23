// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployUSDCVault is Script, DeployHypoVault {
    address constant FACTORY_ADDRESS = address(0x57d2aD92Ff81d3860a6177e15DaAd3E860fb65bE);
    address constant ACCOUNTANT_ADDRESS = address(0xb77fb362e84988e99A08c048a31e94b2CB46Da58);
    address constant DECODER_ADDRESS = address(0xF5680D4B0424ba6431012B2e618838048462eFf8);
    address constant AUTHORITY_ADDRESS = address(0xb722bd369B7ac2388b82A8ecbDeC1dEA02ABe540);

    address constant VAULT_TURNKEY_ADDRESS = address(0x3c1c79d0cfc316Ba959194c89696a8382d7d283b);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v8-usdc"));

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
            "povLendUSDC",
            "Panoptic Lend Vault | USDC",
            salt
        );
        vm.stopBroadcast();
    }
}
