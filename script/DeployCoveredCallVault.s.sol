// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v2-core/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployCoveredCallVault is Script, DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0x3994a6236f6889054d7C11D6B9016C25D0bC18a2);
    address constant ACCOUNTANT_ADDRESS = address(0x0ba79E9964148DdBd185eCD13ee03E321d7b22D9);
    address constant DECODER_ADDRESS = address(0x5388cE7E3d81e0BEe9372c429e4276c20699a1E7);
    address constant AUTHORITY_ADDRESS = address(0x34eC4c475A7fc3B864649007B3C9E6C392043D42);
    address constant PANOPTIC_POOL_ADDRESS = address(0x03AFf7Be6A5afB2bC6830BC54778AF674006850A);

    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0x7A5D178492dbdABcbBc6201D1021BEE145d48604);
    address constant VAULT_TURNKEY_ADDRESS = address(0xC3f99c43960dA8B20872078d57213E9C62E3926e);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-covered-call-usdc"));

    IERC20Partial sepoliaUsdc = IERC20Partial(0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A);
    IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;

        console.log("=== Deploying Covered Call USDC Vault ===");
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
                symbol: "coveredCallUSDC",
                name: "Panoptic Covered Call Vault | USDC",
                salt: salt
            })
        );
        vm.stopBroadcast();
    }
}
