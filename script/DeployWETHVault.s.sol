// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v2-core/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployWETHVault is Script, DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0xA2924c8Bd74Ae84077D082aDeDA2ee78268F7acf);
    address constant ACCOUNTANT_ADDRESS = address(0xF5fE85B6d639FA56E55A8CA5358A1D0384A0A64B);
    address constant DECODER_ADDRESS = address(0xFb32d9323cF3cC2b01218CADa5AbbC6DE93d197b);
    address constant AUTHORITY_ADDRESS = address(0x72E6334d230fDa6A727B619b632e1921F4780d5A);
    address constant PANOPTIC_POOL_ADDRESS = address(0x03AFf7Be6A5afB2bC6830BC54778AF674006850A);

    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0x45f93888565bA53650Af5ceF6279776B0e6B8A92);
    address constant VAULT_TURNKEY_ADDRESS = address(0x8FfA6DAB99f8afc64F61BeF83F0966eD6362f24F);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v9-weth"));

    // Sepolia WETH address
    IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;

        console.log("=== Deploying WETH Vault ===");
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
                underlyingToken: address(sepoliaWeth),
                collateralTracker: COLLATERAL_TRACKER_ADDRESS,
                panopticPool: PANOPTIC_POOL_ADDRESS,
                weth: address(sepoliaWeth),
                canDispatch: false,
                symbol: "povLendWETH",
                name: "Panoptic Lend Vault | WETH",
                salt: salt
            })
        );
        vm.stopBroadcast();
    }
}
