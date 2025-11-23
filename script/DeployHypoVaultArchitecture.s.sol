// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HypoVault} from "../src/HypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {IVaultAccountant} from "../src/interfaces/IVaultAccountant.sol";
import "../src/accountants/PanopticVaultAccountant.sol";
import {MerkleTreeHelper} from "../test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BatchScript} from "lib/forge-safe/src/BatchScript.sol";
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Create2} from "lib/boring-vault/lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import "lib/boring-vault/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

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
contract DeployHypoVaultArchitectureSepolia is BatchScript, MerkleTreeHelper {
    // ISafe PanopticMultisig = ISafe(0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1);
    // TEST SEP multisig
    ISafe PanopticMultisig = ISafe(0x9C44C2B07380DA62a5ea572b886048410b0c44fd);

    // json
    // function run(bool send_) public isBatch(address(PanopticMultisig), "HypoVaultPLPDeployment") {
    function run(bool send_) public isBatch(address(PanopticMultisig)) {
        bool deployFactory = true;

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
        address FeeWallet = TurnkeyAccount0; // TODO: confirm this signer is fine to receive fees
        address BalancerVault = address(0x7777); // Required by ManagerWithMerkleVerification
        IERC20 sepoliaWeth = IERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

        // Note: Each transaction in the batch increments the nonce
        // So if this is the 2nd transaction, use currentNonce + 1
        uint256 currentNonce = PanopticMultisig.nonce();

        // CREATE2
        bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v4"));
        // src: https://github.com/safe-global/safe-deployments/blob/main/src/assets/v1.3.0/create_call.json
        address createCall1_3Sepolia = 0x7cbB62EaA69F79e6873cD1ecB2392971036cFAa4;

        // 1. Deploy reference HypoVault implementation first
        bytes memory hypoVaultImplDeploymentData = type(HypoVault).creationCode;
        bytes memory createImplCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            hypoVaultImplDeploymentData,
            salt // salt for CREATE2
        );
        addToBatch(
            createCall1_3Sepolia,
            0,
            createImplCalldata,
            BatchScript.Operation.DELEGATECALL
        );
        bytes32 hypoVaultImplBytecodeHash = keccak256(hypoVaultImplDeploymentData);
        address hypoVaultImplAddress = Create2.computeAddress(
            salt,
            hypoVaultImplBytecodeHash,
            address(PanopticMultisig)
        );
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Predicted HypoVault implementation Address:", hypoVaultImplAddress);

        // 2. Deploy HypoVaultFactory with correct implementation address as constuctor argument
        // to provide constructor args to create call:
        // bytes memory constructorArgs = abi.encode(arg1, arg2, arg3);
        bytes memory factoryConstructorArgs = abi.encode(hypoVaultImplAddress);
        bytes memory factoryDeploymentData = abi.encodePacked(type(HypoVaultFactory).creationCode, factoryConstructorArgs);
        bytes memory createFactoryCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            factoryDeploymentData, // bytecode + encoded constructor arg
            salt // salt for CREATE2
        );
        addToBatch(
            createCall1_3Sepolia,
            0,
            createFactoryCalldata,
            BatchScript.Operation.DELEGATECALL
        );
        bytes32 factoryBytecodeHash = keccak256(factoryDeploymentData);
        address vaultFactoryAddress = Create2.computeAddress(
            salt,
            factoryBytecodeHash,
            address(PanopticMultisig) // The Safe will be the deployer via DelegateCall
        );
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Predicted Factory Address:", vaultFactoryAddress);
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

        // Deploy HypoVault
        HypoVaultFactory vaultFactory = HypoVaultFactory(vaultFactoryAddress);

        // Prepare vault creation calldata
        uint256 performanceFeeBps = 1000; // 10%
        bytes memory createVaultCalldata = abi.encodeWithSelector(
            vaultFactory.createVault.selector,
            address(sepoliaWeth),
            PanopticMultisig,
            IVaultAccountant(address(accountantAddress)),
            performanceFeeBps,
            "povLendWETH",
            "Panoptic Lend Vault | WETH",
            salt
        );
        addToBatch(
            vaultFactoryAddress,
            0,
            createVaultCalldata,
            BatchScript.Operation.DELEGATECALL
        );

        address wethPlpVaultAddress = Clones.predictDeterministicAddress(
            hypoVaultImplAddress,
            salt,
            address(PanopticMultisig)
        );
        HypoVault wethPlpVault = HypoVault(payable(wethPlpVaultAddress));

        bytes memory setFeeWalletCalldata = abi.encodeWithSelector(
            wethPlpVault.setFeeWallet.selector,
            FeeWallet
        );
        addToBatch(
            address(wethPlpVault),
            0,
            setFeeWalletCalldata,
            BatchScript.Operation.DELEGATECALL
        );
        /**************
         END HYPOVAULT DEPLOYMENT
        **********/

       // TODO: add rest of transactions to the gnosis safe batch: remaining contract deployments, accountant pool hash updating, merkle root generation and json dumping,
       // setting of manageRoot for multisig and turnkey signer, from PLPVaultIntegrationTest.t.sol.
        //ignore any test assertions and call
       // out anything that may not work due to vm.prank calls

        // Deploy Manager and set on PLP Vault
        // Manager
        // HypoVaultManagerWithMerkleVerification wethPlpVaultManager = new HypoVaultManagerWithMerkleVerification(
        //         PanopticMultisig,
        //         address(wethPlpVault),
        //         BalancerVault
        //     );

        // wethPlpVault.setManager(address(wethPlpVaultManager));
        /**************
         END MANAGER DEPLOYMENT
        **********/

        // Propose all txns to safe
        // executeBatch(send_, currentNonce);
    }
}
