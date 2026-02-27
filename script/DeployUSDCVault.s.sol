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
    address constant FACTORY_ADDRESS = address(0xC631ea9659A255641C0ee28C18f2F23970DD3DdD);
    address constant ACCOUNTANT_ADDRESS = address(0x061AF4Fd2a015ed871e7EA406749cF268236C918);
    address constant DECODER_ADDRESS = address(0x3c2D182DB402Fc649aea61731CE47Ea72Ab3a7f1);
    address constant AUTHORITY_ADDRESS = address(0x183b19b0c27f5124E077b10fa57f3B19e71958B2);
    address constant PANOPTIC_POOL_ADDRESS = address(0x5D44F6574B8dE88ffa2CCAEba0B07aD3C204571E);

    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0xe2BD879109f84313AC986B2390110F5A240a9fa9);
    address constant VAULT_TURNKEY_ADDRESS = address(0x3c1c79d0cfc316Ba959194c89696a8382d7d283b);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-usdc"));

    IERC20Partial sepoliaUsdc = IERC20Partial(0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A);
    IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

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
            PANOPTIC_POOL_ADDRESS,
            address(sepoliaWeth),
            "povLendUSDC",
            "Panoptic Lend Vault | USDC",
            salt
        );
        vm.stopBroadcast();
    }
}
