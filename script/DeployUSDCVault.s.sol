// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v2-core/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployUSDCVault is Script, DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0x363a9d605ca45cBfF3b597350DeADb53cdC292c7);
    address constant ACCOUNTANT_ADDRESS = address(0x25BBef1DF262c24aa1AACD1F7eCeEcc1a7AD08ab);
    address constant DECODER_ADDRESS = address(0xb899BE50BAF25BBB3A3ca3403256B3c703E5AB5d);
    address constant AUTHORITY_ADDRESS = address(0x673BfafB4e2712215B422347c1571421B83E8A3d);
    address constant PANOPTIC_POOL_ADDRESS = address(0x03AFf7Be6A5afB2bC6830BC54778AF674006850A);

    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0x7A5D178492dbdABcbBc6201D1021BEE145d48604);
    address constant VAULT_TURNKEY_ADDRESS = address(0x3c1c79d0cfc316Ba959194c89696a8382d7d283b);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-usdc"));

    IERC20Partial sepoliaUsdc = IERC20Partial(0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A);
    IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;

        console.log("=== Deploying USDC PLP Vault ===");
        console.log("Deployer:", deployer);
        console.log("Using Factory:", FACTORY_ADDRESS);
        console.log("Using Accountant:", ACCOUNTANT_ADDRESS);
        console.log("Using Decoder:", DECODER_ADDRESS);
        console.log("Using Authority:", AUTHORITY_ADDRESS);

        deployVault(
            DeployStruct({
                deployer: deployer,
                vaultFactory: FACTORY_ADDRESS,
                accountantAddress: ACCOUNTANT_ADDRESS,
                collateralTrackerDecoderAndSanitizer: DECODER_ADDRESS,
                authorityAddress: AUTHORITY_ADDRESS,
                turnkeyAccount: VAULT_TURNKEY_ADDRESS,
                underlyingToken: address(sepoliaUsdc),
                collateralTracker: COLLATERAL_TRACKER_ADDRESS,
                panopticPool: PANOPTIC_POOL_ADDRESS,
                weth: address(sepoliaWeth),
                symbol: "plpUSDC",
                name: "Panoptic USDC PLP Vault",
                salt: salt
            })
        );
        vm.stopBroadcast();
    }
}
