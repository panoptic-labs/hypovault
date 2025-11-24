// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CollateralTrackerDecoderAndSanitizer} from "../src/DecodersAndSanitizers/CollateralTrackerDecoderAndSanitizer.sol";
import {ERC4626} from "lib/boring-vault/lib/solmate/src/tokens/ERC4626.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HypoVault} from "../src/HypoVault.sol";
import {HypoVaultFactory} from "../src/HypoVaultFactory.sol";
import {IVaultAccountant} from "../src/interfaces/IVaultAccountant.sol";
import "../src/accountants/PanopticVaultAccountant.sol";
import {MerkleTreeHelper} from "../test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {BatchScript} from "lib/forge-safe/src/BatchScript.sol";
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {Create2} from "lib/boring-vault/lib/openzeppelin-contracts/contracts/utils/Create2.sol";
import "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import "lib/boring-vault/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import {HypoVaultManagerWithMerkleVerification} from "../src/managers/HypoVaultManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {Auth} from "lib/boring-vault/lib/solmate/src/auth/Auth.sol";

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

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
        address FeeWallet = TurnkeyAccount0; // TODO: confirm this signer is fine to receive fees
        address BalancerVaultAddr = address(0x7777); // Required by ManagerWithMerkleVerification
        IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

        // Note: Each transaction in the batch increments the nonce
        // So if this is the 2nd transaction, use currentNonce + 1
        uint256 currentNonce = PanopticMultisig.nonce();

        // CREATE2
        bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v4"));
        // src: https://github.com/safe-global/safe-deployments/blob/main/src/assets/v1.3.0/create_call.json
        address createCall1_3Sepolia = 0x7cbB62EaA69F79e6873cD1ecB2392971036cFAa4;
        // address createCall1_5Sepolia = 0x2Ef5ECfbea521449E4De05EDB1ce63B75eDA90B4;
        address createCall = createCall1_3Sepolia;

        // 1. Deploy reference HypoVault implementation first
        bytes memory hypoVaultImplDeploymentData = type(HypoVault).creationCode;
        bytes memory createImplCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            hypoVaultImplDeploymentData,
            salt // salt for CREATE2
        );
        addToBatch(createCall, 0, createImplCalldata, BatchScript.Operation.DELEGATECALL);
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
        bytes memory factoryDeploymentData = abi.encodePacked(
            type(HypoVaultFactory).creationCode,
            factoryConstructorArgs
        );
        bytes memory createFactoryCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            factoryDeploymentData, // bytecode + encoded constructor arg
            salt // salt for CREATE2
        );
        addToBatch(createCall, 0, createFactoryCalldata, BatchScript.Operation.DELEGATECALL);
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
            createCall, // to: CreateCall contract
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
        // TODO: should this be call or delegate call? i think just call. bc you want the factory to be the sender
        addToBatch(vaultFactoryAddress, 0, createVaultCalldata, BatchScript.Operation.CALL);

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
        console.log("setting fee wallet");
        addToBatch(address(wethPlpVault), 0, setFeeWalletCalldata, BatchScript.Operation.CALL);
        console.log("set fee wallet");
        /**************
         END HYPOVAULT DEPLOYMENT
        **********/

        /*
            Add the remaining core production transactions to the batch that were performed by hand in PLPVaultIntegrationTest.t.sol.
            ** Do NOT copy test vm calls (vm.prank, vm.stopPrank, assertions, or cheats).
            ** Only include calls that correspond to actual system changes required in a deployment!
        */

        // ------------------------
        // 1. PanopticVaultAccountant already deployed and set via accountantAddress
        // 2. HypoVault deployed above as wethPlpVault
        // 3. Set FeeWallet executed above for wethPlpVault
        // 4. Deploy (instantiate) HypoVaultManagerWithMerkleVerification, passing multisig, vault, balancer address
        // ------------------------
        // NOTE: Any constructor arguments must be correctly configured per your environment!!
        bytes memory managerDeployCalldata = abi.encodePacked(
            type(HypoVaultManagerWithMerkleVerification).creationCode,
            abi.encode(PanopticMultisig, address(wethPlpVault), BalancerVaultAddr)
        );
        bytes memory createManagerCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            managerDeployCalldata,
            salt
        );
        addToBatch(createCall, 0, createManagerCalldata, BatchScript.Operation.DELEGATECALL);
        address predictedManagerAddress = Create2.computeAddress(
            bytes32(salt),
            keccak256(managerDeployCalldata),
            address(PanopticMultisig)
        );
        console.log("predictedManagerAddress: ", predictedManagerAddress);

        // 5. Set HypoVault manager
        bytes memory setManagerCalldata = abi.encodeWithSelector(
            wethPlpVault.setManager.selector,
            predictedManagerAddress
        );
        addToBatch(address(wethPlpVault), 0, setManagerCalldata, BatchScript.Operation.CALL);

        // ------------------------
        // 6. Set up DecoderAndSantizer that can handle all functions that will be called  + set up Merkle roots for strategist + safe
        //    In real solution, call MerkleTreeHelper to generate ManageLeaf[], build tree, and dump JSON for operations offchain.
        //    Assume you have something like:
        //      bytes32 manageRoot = <build this using MerkleTreeHelper and correct leaves, as in PLPVaultIntegrationTest.t.sol>
        //    For deployment, you should use the actual desired merkle root built off-chain and hardcoded here.
        // ------------------------
        // Build merkle root and dump to JSON
        address wethUsdc500bpsV3Collateral0 = 0x1AF0D98626d53397BA5613873D3b19cc25235d52;
        // Deploy CollateralTrackerDecoderAndSanitizer with CREATE2
        // Note: Constructor takes the vault address as argument
        bytes memory decoderConstructorArgs = abi.encode(address(wethPlpVault));
        bytes memory decoderDeploymentData = abi.encodePacked(
            type(CollateralTrackerDecoderAndSanitizer).creationCode,
            decoderConstructorArgs
        );
        bytes memory createDecoderCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0, // value (no ETH sent)
            decoderDeploymentData, // contract bytecode + constructor args
            salt // salt for CREATE2
        );
        addToBatch(
            createCall, // to: CreateCall contract
            0, // value: 0 ETH
            createDecoderCalldata, // data: performCreate2 call
            BatchScript.Operation.DELEGATECALL // operation: 1 = DelegateCall (CRITICAL!)
        );
        bytes32 decoderBytecodeHash = keccak256(decoderDeploymentData);
        address collateralTrackerDecoderAndSanitizer = Create2.computeAddress(
            salt,
            decoderBytecodeHash,
            address(PanopticMultisig) // The Safe will be the deployer via DelegateCall
        );
        console.log("=== CREATE2 Deployment Info ===");
        console.log(
            "Predicted CollateralTrackerDecoderAndSanitizer Address:",
            collateralTrackerDecoderAndSanitizer
        );

        setSourceChainName(sepolia);
        setAddress(false, sepolia, "boringVault", address(wethPlpVault));
        setAddress(false, sepolia, "managerAddress", predictedManagerAddress);
        setAddress(false, sepolia, "accountantAddress", accountantAddress);
        setAddress(
            false,
            sepolia,
            "rawDataDecoderAndSanitizer",
            collateralTrackerDecoderAndSanitizer
        );

        ManageLeaf[] memory leafs = new ManageLeaf[](8); // limit to smallest power of 2 that is greater than leaf size

        _addCollateralTrackerLeafs(leafs, ERC4626(wethUsdc500bpsV3Collateral0));

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // Save tree to JSON for debugging
        string memory filePath = "./leafs/ProductionPLPStrategistLeaves.json";
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        _generateLeafs(filePath, leafs, manageRoot, manageTree);

        console.log("Generated manageRoot:");
        console.logBytes32(manageRoot);

        // Set manageRoot for both multisig and turnkey

        bytes memory setManageRootMultisigCalldata = abi.encodeWithSelector(
            // setManageRoot not defined on HypoVaultManager...Verification,
            // defined on parent. Have to get selector from parent contract.
            // HypoVaultManagerWithMerkleVerification.setManageRoot.selector,
            ManagerWithMerkleVerification.setManageRoot.selector,
            PanopticMultisig,
            manageRoot
        );
        addToBatch(
            predictedManagerAddress,
            0,
            setManageRootMultisigCalldata,
            BatchScript.Operation.CALL
        );
        bytes memory setManageRootTurnkeyCalldata = abi.encodeWithSelector(
            ManagerWithMerkleVerification.setManageRoot.selector,
            TurnkeyAccount0,
            manageRoot
        );
        addToBatch(
            predictedManagerAddress,
            0,
            setManageRootTurnkeyCalldata,
            BatchScript.Operation.CALL
        );

        // ------------------------
        // 7. Deploy and configure RolesAuthority (authority contract).
        // NOTE: In real deploy, make sure only one authority per system is used; here it's batched for deployment.
        // ------------------------
        bytes memory authorityDeployCalldata = abi.encodePacked(
            type(RolesAuthority).creationCode,
            abi.encode(PanopticMultisig, Authority(address(0)))
        );
        bytes memory createAuthorityCalldata = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector,
            0,
            authorityDeployCalldata,
            salt
        );
        addToBatch(createCall, 0, createAuthorityCalldata, BatchScript.Operation.DELEGATECALL);
        address predictedAuthorityAddress = Create2.computeAddress(
            salt,
            keccak256(authorityDeployCalldata),
            address(PanopticMultisig)
        );
        console.log("predictedAuthorityAddress: ", predictedAuthorityAddress);

        // Set RolesAuthority as authority on HypoVaultManagerWithMerkleVerification
        bytes memory setAuthorityCalldata = abi.encodeWithSelector(
            // HypoVaultManagerWithMerkleVerification.setAuthority.selector,
            // inherited from Auth
            Auth.setAuthority.selector,
            Authority(predictedAuthorityAddress)
        );
        addToBatch(predictedManagerAddress, 0, setAuthorityCalldata, BatchScript.Operation.CALL);

        // ------------------------
        // 8. Grant roles, set up access control for Turnkey (STRATEGIST_ROLE, selectors)
        //    Grant STRATEGIST_ROLE to TurnkeyAccount0
        //    Assign proper capabilities to role (fulfillDeposits, fulfillWithdrawals, cancelDeposit, manageVaultWithMerkleVerification) on manager
        // ------------------------
        uint8 STRATEGIST_ROLE = 7;
        bytes memory setRoleCalldata = abi.encodeWithSelector(
            RolesAuthority.setUserRole.selector,
            TurnkeyAccount0,
            STRATEGIST_ROLE,
            true
        );
        addToBatch(predictedAuthorityAddress, 0, setRoleCalldata, BatchScript.Operation.CALL);

        // Set abilities/capabilities for STRATEGIST_ROLE
        bytes4[] memory strategistSelectors = new bytes4[](4);
        strategistSelectors[0] = HypoVaultManagerWithMerkleVerification.fulfillDeposits.selector;
        strategistSelectors[1] = HypoVaultManagerWithMerkleVerification.fulfillWithdrawals.selector;
        strategistSelectors[2] = HypoVaultManagerWithMerkleVerification.cancelDeposit.selector;
        strategistSelectors[3] = bytes4(
            keccak256(
                "manageVaultWithMerkleVerification(bytes32[][],address[],address[],bytes[],uint256[])"
            )
        );
        for (uint i = 0; i < strategistSelectors.length; i++) {
            bytes memory setRoleCapabilityCalldata = abi.encodeWithSelector(
                RolesAuthority.setRoleCapability.selector,
                STRATEGIST_ROLE,
                predictedManagerAddress,
                strategistSelectors[i],
                true
            );
            addToBatch(
                predictedAuthorityAddress,
                0,
                setRoleCapabilityCalldata,
                BatchScript.Operation.CALL
            );
        }

        // ------------------------
        // 9. (Optional, but suggested) Update PanopticVaultAccountant pools hash for vault
        // You must precompute the correct poolInfosHash offchain or build it in the script using struct values
        // Example hash below should be replaced with actual hash matching protocol config
        // ------------------------
        // Build pools hash
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createDefaultPools();
        bytes32 poolInfosHash = keccak256(abi.encode(poolInfos));
        console.log("Generated poolInfosHash:");
        console.logBytes32(poolInfosHash);
        bytes memory updatePoolsHashCalldata = abi.encodeWithSelector(
            PanopticVaultAccountant.updatePoolsHash.selector,
            address(wethPlpVault),
            poolInfosHash
        );
        addToBatch(accountantAddress, 0, updatePoolsHashCalldata, BatchScript.Operation.CALL);

        // ------------------------
        // 10. (Optional) Dump JSON of Merkle Tree/leaves for reference. Should be handled offchain, but call included here for completeness.
        // The file dump is not a chain call: do offchain before deployment.
        // _generateLeafs(filePath, leafs, manageRoot, manageTree);

        // Propose all txns to safe
        executeBatch(send_, currentNonce);
    }

    function createDefaultPools() internal returns (PanopticVaultAccountant.PoolInfo[] memory) {
        int24 TWAP_TICK = 100;
        int24 MAX_PRICE_DEVIATION = 1700000; // basically no price deviation check for deployment
        uint32 TWAP_WINDOW = 600; // 10 minutes

        // i think the uniswapv3 pool is the oracle
        // Deploy mock oracles (replace with real oracle addresses for production)
        IV3CompatibleOracle wethUsdc500bpsV3UniswapPool = IV3CompatibleOracle(
            0x1105514b9Eb942F2596A2486093399b59e2F23fC
        );
        IV3CompatibleOracle poolOracle = wethUsdc500bpsV3UniswapPool;
        IV3CompatibleOracle oracle0 = wethUsdc500bpsV3UniswapPool;
        IV3CompatibleOracle oracle1 = wethUsdc500bpsV3UniswapPool;

        address token0 = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // sepolia weth9
        address token1 = 0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A; // sepolia mock USDC
        address wethUsdc500bpsV3PanopticPool = 0x00002c1c2EF3E4b606F8361d975Cdc2834668e9F;

        PanopticVaultAccountant.PoolInfo[] memory pools = new PanopticVaultAccountant.PoolInfo[](1);
        pools[0] = PanopticVaultAccountant.PoolInfo({
            pool: PanopticPool(wethUsdc500bpsV3PanopticPool),
            token0: IERC20Partial(token0),
            token1: IERC20Partial(token1),
            poolOracle: poolOracle,
            oracle0: oracle0,
            isUnderlyingToken0InOracle0: true, // true because token0 is WETH and we're deploying a WETH vault
            oracle1: oracle1,
            isUnderlyingToken0InOracle1: false,
            maxPriceDeviation: MAX_PRICE_DEVIATION,
            twapWindow: TWAP_WINDOW
        });
        return pools;
    }
}
