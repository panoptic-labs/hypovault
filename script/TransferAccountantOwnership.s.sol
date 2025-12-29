// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {HypoVault} from "../src/HypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import "../src/accountants/PanopticVaultAccountant.sol";
import {Script} from "forge-std/Script.sol";

contract TransferAccountantOwnership is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);

        PanopticVaultAccountant a = PanopticVaultAccountant(
            0x425379d80bf1ED904006B3C893BEa1903Fc13caF
        );

        a.transferOwnership(TurnkeyAccount0);
        vm.stopBroadcast();
    }
}
