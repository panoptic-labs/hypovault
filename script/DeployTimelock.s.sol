// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {TimelockController} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {ChainConfig} from "./helpers/ChainConfig.sol";

interface IOwnableTransfer {
    function transferOwnership(address newOwner) external;
}

contract DeployTimelock is Script, ChainConfig {
    bytes32 salt = keccak256(abi.encodePacked("hypovault-timelock-v1"));

    uint256 constant TIMELOCK_MAX_DELAY = 30 days;

    function run() public {
        Config memory c = getChainConfig();

        require(c.panopticMultisig != address(0), "proposer (multisig) is zero address");
        require(c.timelockMinDelay <= TIMELOCK_MAX_DELAY, "timelockMinDelay exceeds max delay");

        vm.startBroadcast();

        // 1. Deploy the TimelockController.
        // admin = address(0) -> self-administered: DEFAULT_ADMIN_ROLE is granted only
        // to the timelock itself, so role changes must also go through the delay.
        address[] memory proposers = new address[](1);
        proposers[0] = c.panopticMultisig;

        // Open execution: anyone can execute a ready operation.
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        TimelockController timelock = new TimelockController{salt: salt}(
            c.timelockMinDelay,
            proposers,
            executors,
            address(0)
        );

        console.log("=== TimelockController Deployed ===");
        console.log("Timelock:", address(timelock));
        console.log("minDelay (s):", c.timelockMinDelay);
        console.log("Proposer/Canceller (multisig):", c.panopticMultisig);
        console.log("Executor:", executors[0]);

        // 2. Hand over ownership of every owned contract.
        _transfer("HypoVault (USDC)", c.usdcVault, address(timelock));
        _transfer("HypoVault (WETH)", c.wethVault, address(timelock));
        _transfer("Manager (USDC)", c.usdcManager, address(timelock));
        _transfer("Manager (WETH)", c.wethManager, address(timelock));
        _transfer("PanopticVaultAccountant", c.accountant, address(timelock));
        _transfer("RolesAuthority", c.authority, address(timelock));

        vm.stopBroadcast();

        console.log("=== Ownership Transfer Complete ===");
        console.log("All listed contracts now owned by:", address(timelock));
    }

    function _transfer(string memory label, address target, address newOwner) internal {
        IOwnableTransfer(target).transferOwnership(newOwner);
        console.log(string.concat(label, " ownership transferred"));
        console.log("  target:", target);
        console.log("  newOwner:", newOwner);
    }
}
