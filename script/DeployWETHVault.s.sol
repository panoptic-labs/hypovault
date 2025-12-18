// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {PanopticVaultAccountant} from "../src/accountants/PanopticVaultAccountant.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {console} from "forge-std/console.sol";

contract DeployWETHVault is DeployHypoVault {
    // Addresses from the initial deployment
    address constant FACTORY_ADDRESS = address(0x57d2aD92Ff81d3860a6177e15DaAd3E860fb65bE);
    address constant ACCOUNTANT_ADDRESS = address(0xb77fb362e84988e99A08c048a31e94b2CB46Da58);
    address constant DECODER_ADDRESS = address(0xF5680D4B0424ba6431012B2e618838048462eFf8);
    address constant AUTHORITY_ADDRESS = address(0xb722bd369B7ac2388b82A8ecbDeC1dEA02ABe540);

    address constant VAULT_TURNKEY_ADDRESS = address(0x8FfA6DAB99f8afc64F61BeF83F0966eD6362f24F);

    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v8-weth"));

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
            FACTORY_ADDRESS,
            ACCOUNTANT_ADDRESS,
            DECODER_ADDRESS,
            AUTHORITY_ADDRESS,
            VAULT_TURNKEY_ADDRESS,
            address(sepoliaWeth),
            "povLendWETH",
            "Panoptic Lend Vault | WETH",
            salt
        );
        vm.stopBroadcast();
    }
}
