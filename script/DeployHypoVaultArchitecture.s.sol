// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import "../src/accountants/PanopticVaultAccountant.sol";
import {BatchScript} from "lib/forge-safe/src/BatchScript.sol";
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Create2} from "lib/boring-vault/lib/openzeppelin-contracts/contracts/utils/Create2.sol";

interface ISafe {
    /**
     * @dev Returns the current nonce of the Safe.
     * This is the number of the next pending transaction from this Safe.
     */
    function nonce() external view returns (uint256);
}

// Interface for CreateCall contract
interface ICreateCall {
    function performCreate2(
        uint256 value,
        bytes memory deploymentData,
        bytes32 salt
    ) external returns (address newContract);
}

// Intended to be sent from the PanopticMultisig
// Use forge-safe to output transaction batch to gnosis safe
// Do not run from EOA (though you could, if you safely transferred ownership)
contract DeployHypoVaultArchitectureSepolia is BatchScript {
    // ISafe PanopticMultisig = ISafe(0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1);
    // TEST SEP multisig
    ISafe PanopticMultisig = ISafe(0x9C44C2B07380DA62a5ea572b886048410b0c44fd);

    // json
    // function run(bool send_) public isBatch(address(PanopticMultisig), "HypoVaultPLPDeployment") {
    function run(bool send_) public isBatch(address(PanopticMultisig)) {
        bool deployFactory = true;

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
        address BalancerVault = address(0x7777); // Required by ManagerWithMerkleVerification
        IERC20 sepoliaWeth = IERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

        // Note: Each transaction in the batch increments the nonce
        // So if this is the 2nd transaction, use currentNonce + 1
        uint256 currentNonce = PanopticMultisig.nonce();

        // CREATE2
        bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v1"));
        // src: https://github.com/safe-global/safe-deployments/blob/main/src/assets/v1.3.0/create_call.json
        address createCall1_3Sepolia = 0x7cbB62EaA69F79e6873cD1ecB2392971036cFAa4;

        // Deploy HypoVaultFactory
        // Deploy a new contract
        // w/ constructor args
        // bytes memory constructorArgs = abi.encode(arg1, arg2, arg3);
        // bytes memory deploymentData = abi.encodePacked(type(HypoVaultFactory).creationCode, constructorArgs);
        // w/o constructor args
        bytes memory factoryDeploymentData = type(HypoVaultFactory).creationCode;
        // Predict the deployed address
        bytes memory createFactoryCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            factoryDeploymentData, // contract bytecode + constructor args
            salt // salt for CREATE2
        );
        addToBatch(
            createCall1_3Sepolia, // to: CreateCall contract
            0, // value: 0 ETH
            createFactoryCalldata, // data: performCreate2 call
            BatchScript.Operation.DELEGATECALL // operation: 1 = DelegateCall (CRITICAL!)
        );
        bytes32 factoryBytecodeHash = keccak256(factoryDeploymentData);
        address factoryAddress = Create2.computeAddress(
            salt,
            factoryBytecodeHash,
            address(PanopticMultisig) // The Safe will be the deployer via DelegateCall
        );
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Predicted Factory Address:", factoryAddress);
        /**************
         END FACTORY DEPLOYMENT
        **********/

        // Deploy new Accountant
        // TODO: no constructor args, but owner is set to msg.sender. delegatecall should ensure the owner is the safe, but verify this after deployment
        bytes memory accountantDeploymentData = type(PanopticVaultAccountant).creationCode;
        bytes memory createAccountantCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            accountantDeploymentData, // contract bytecode + constructor args
            salt // salt for CREATE2
        );
        addToBatch(
            createCall1_3Sepolia, // to: CreateCall contract
            0, // value: 0 ETH
            createAccountantCalldata, // data: performCreate2 call
            BatchScript.Operation.DELEGATECALL // operation: 1 = DelegateCall (CRITICAL!)
        );
        bytes32 accountantBytecodeHash = keccak256(accountantDeploymentData);
        address accountantAddress = Create2.computeAddress(
            salt,
            accountantBytecodeHash,
            address(PanopticMultisig) // The Safe will be the deployer via DelegateCall
        );
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Predicted accountant Address:", accountantAddress);
        /**************
         END ACCOUNTANT DEPLOYMENT
        **********/

        // TODO: Deploy HypoVault via HypoVault factory
        // This is made exceptionally difficult and flaky to do in one transaction because HypoVault relies on the nonce of the Factory contract. We need to know the address inside this transaction, so we can atomically set things like Vault.feeWallet and Vault.manager, but it's hard to know reliably since nonce will be frozen at the time of transaction proposal and can change between proposal and signing time.

        // so we need to deploy vaults with create2. the most standard way to do that is implement Factory pattern with cloning

        /**************
         END HYPOVAULT DEPLOYMENT
        **********/

        // Propose all txns to safe
        executeBatch(send_, currentNonce);
    }
}
