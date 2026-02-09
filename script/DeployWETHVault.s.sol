// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract DeployWETHVault is Script, DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0x5d24AeA981D6e5F38A21Cfe5b81204D2F6225271);
    address constant ACCOUNTANT_ADDRESS = address(0x6100455aA6637093464E75a9Cb9785F7A8D51E80);
    address constant DECODER_ADDRESS = address(0x606c4Aee942f2F0dCd0c0934E4266eb854EA0cBe);
    address constant AUTHORITY_ADDRESS = address(0x9166293A301CcC805d5171A2D1e62050ba72795D);
    address constant COLLATERAL_TRACKER_ADDRESS =
        address(0x4f29B472bebbFcEEc250a4A5BC33312F00025600);

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
            deployer,
            FACTORY_ADDRESS,
            ACCOUNTANT_ADDRESS,
            DECODER_ADDRESS,
            AUTHORITY_ADDRESS,
            VAULT_TURNKEY_ADDRESS,
            address(sepoliaWeth),
            COLLATERAL_TRACKER_ADDRESS,
            address(0), // panopticPool not needed for this vault
            "povLendWETH",
            "Panoptic Lend Vault | WETH",
            salt
        );
        vm.stopBroadcast();
    }
}
