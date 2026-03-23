// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployHypoVault} from "./helpers/DeployHypoVault.sol";
import {ChainConfig} from "./helpers/ChainConfig.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

// Usage: CHAIN_NAME=sepolia forge script script/DeployWETHVault.s.sol --rpc-url sepolia --sender <addr> -vvvv --broadcast --verify
contract DeployWETHVault is Script, DeployHypoVault, ChainConfig {
    function run() public {
        Config memory c = getChainConfig();

        vm.startBroadcast();
        deployVault(
            DeployStruct({
                deployer: msg.sender,
                vaultFactory: c.factory,
                accountantAddress: c.accountant,
                collateralTrackerDecoderAndSanitizer: c.decoder,
                authorityAddress: c.authority,
                turnkeyAccount: WETH_TURNKEY,
                underlyingToken: c.weth,
                collateralTracker: c.wethCollateralTracker,
                panopticPool: c.panopticPool,
                weth: c.weth,
                token0: c.token0,
                token1: c.token1,
                chainName: c.chainName,
                symbol: "plpWETH",
                name: "Panoptic WETH PLP Vault",
                salt: keccak256(abi.encodePacked(WETH_VAULT_SALT))
            })
        );
        vm.stopBroadcast();
    }
}
