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
    address constant FACTORY_ADDRESS = address(0xebb431ca19A7B245A0827BFA08b5167694B75F38);
    address constant ACCOUNTANT_ADDRESS = address(0x529e41f74221963D43B0b4466674EA24A19F1c27);
    address constant DECODER_ADDRESS = address(0x045AB155Ee70f57fc1672f100FE4939a0d052731);
    address constant AUTHORITY_ADDRESS = address(0xa1FC02EEeDb96F9C0231234DB2824c1FfFeD60CD);
    address constant COLLATERAL_TRACKER_ADDRESS = address(0x1AF0D98626d53397BA5613873D3b19cc25235d52);

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
            "povLendWETH",
            "Panoptic Lend Vault | WETH",
            salt
        );
        vm.stopBroadcast();
    }
}
