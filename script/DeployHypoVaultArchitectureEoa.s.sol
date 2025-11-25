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
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {HypoVaultManagerWithMerkleVerification} from "../src/managers/HypoVaultManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";

// Intended to be run from an EOA using vm.startBroadcast/stopBroadcast
contract DeployHypoVaultArchitectureEoa is Script, MerkleTreeHelper {
    // Real Panoptic multisig
    // ISafe PanopticMultisig = ISafe(0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1);
    // @dev - test Safe on sepolia. NOT the real multisig.
    address PanopticMultisig = address(0x9C44C2B07380DA62a5ea572b886048410b0c44fd);

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
    address BalancerVaultAddr = address(0x7777); // Required by ManagerWithMerkleVerification
    IERC20Partial sepoliaWeth = IERC20Partial(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

    // CREATE2 salt
    bytes32 salt = keccak256(abi.encodePacked("my-unique-salt-v6"));

    function run() public {
        address owner = msg.sender;

        console.log("=== Deployer Address ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy reference HypoVault implementation with CREATE2
        HypoVault hypoVaultImpl = new HypoVault{salt: salt}();
        address hypoVaultImplAddress = address(hypoVaultImpl);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("HypoVault implementation Address:", hypoVaultImplAddress);

        // 2. Deploy HypoVaultFactory with CREATE2
        HypoVaultFactory vaultFactory = new HypoVaultFactory{salt: salt}(hypoVaultImplAddress);
        address vaultFactoryAddress = address(vaultFactory);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Factory Address:", vaultFactoryAddress);

        // 3. Deploy new Accountant with CREATE2
        PanopticVaultAccountant accountant = new PanopticVaultAccountant{salt: salt}(owner);
        address accountantAddress = address(accountant);
        console.log("=== CREATE2 Deployment Info ===");
        console.log("Accountant Address:", accountantAddress);

        // 4. Deploy HypoVault via Factory
        uint256 performanceFeeBps = 1000; // 10%
        address wethPlpVaultAddress = vaultFactory.createVault(
            address(sepoliaWeth),
            owner,
            IVaultAccountant(accountantAddress),
            performanceFeeBps,
            "povLendWETH",
            "Panoptic Lend Vault | WETH",
            salt
        );
        HypoVault wethPlpVault = HypoVault(payable(wethPlpVaultAddress));
        console.log("wethPlpVaultAddress: ", wethPlpVaultAddress);

        // 5. Set Fee Wallet
        wethPlpVault.setFeeWallet(TurnkeyAccount0);
        console.log("Set fee wallet to:", TurnkeyAccount0);

        // 6. Deploy HypoVaultManagerWithMerkleVerification with CREATE2
        HypoVaultManagerWithMerkleVerification manager = new HypoVaultManagerWithMerkleVerification{
            salt: salt
        }(owner, address(wethPlpVault), BalancerVaultAddr);
        address managerAddress = address(manager);
        console.log("Manager Address:", managerAddress);

        // 7. Set HypoVault manager
        wethPlpVault.setManager(managerAddress);
        console.log("Manager set on vault");

        // 8. Deploy CollateralTrackerDecoderAndSanitizer with CREATE2
        address wethUsdc500bpsV3Collateral0 = 0x1AF0D98626d53397BA5613873D3b19cc25235d52;
        CollateralTrackerDecoderAndSanitizer decoder = new CollateralTrackerDecoderAndSanitizer{
            salt: salt
        }(address(wethPlpVault));
        address collateralTrackerDecoderAndSanitizer = address(decoder);
        console.log("=== CREATE2 Deployment Info ===");
        console.log(
            "CollateralTrackerDecoderAndSanitizer Address:",
            collateralTrackerDecoderAndSanitizer
        );

        // 9. Build merkle tree for manage operations
        setSourceChainName(sepolia);
        setAddress(false, sepolia, "boringVault", address(wethPlpVault));
        setAddress(false, sepolia, "managerAddress", managerAddress);
        setAddress(false, sepolia, "accountantAddress", accountantAddress);
        setAddress(
            false,
            sepolia,
            "rawDataDecoderAndSanitizer",
            collateralTrackerDecoderAndSanitizer
        );

        ManageLeaf[] memory leafs = new ManageLeaf[](8);
        _addCollateralTrackerLeafs(leafs, ERC4626(wethUsdc500bpsV3Collateral0));
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        string memory filePath = "./leafs/ProductionWETHPLPStrategistLeaves.json";
        _generateLeafs(filePath, leafs, manageRoot, manageTree); // Dump tree and leaves to JSON. Useful for SDK later.

        console.log("Generated manageRoot:");
        console.logBytes32(manageRoot);

        // 10. Set manageRoot for both multisig and turnkey
        manager.setManageRoot(PanopticMultisig, manageRoot);
        manager.setManageRoot(TurnkeyAccount0, manageRoot);
        console.log("ManageRoot set for multisig and turnkey");

        // 11. Deploy and configure RolesAuthority with CREATE2
        RolesAuthority authority = new RolesAuthority{salt: salt}(owner, Authority(address(0)));
        address authorityAddress = address(authority);
        console.log("RolesAuthority Address:", authorityAddress);

        // 12. Set RolesAuthority as authority on HypoVaultManagerWithMerkleVerification
        manager.setAuthority(Authority(authorityAddress));
        console.log("Authority set on manager");

        // 13. Grant STRATEGIST_ROLE to TurnkeyAccount0
        uint8 STRATEGIST_ROLE = 7;
        authority.setUserRole(TurnkeyAccount0, STRATEGIST_ROLE, true);
        console.log("STRATEGIST_ROLE granted to:", TurnkeyAccount0);

        // 14. Set abilities/capabilities for STRATEGIST_ROLE
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
            authority.setRoleCapability(
                STRATEGIST_ROLE,
                managerAddress,
                strategistSelectors[i],
                true
            );
        }
        console.log("STRATEGIST_ROLE capabilities set");

        // 15. Update PanopticVaultAccountant pools hash for vault
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createDefaultPools();
        bytes32 poolInfosHash = keccak256(abi.encode(poolInfos));
        console.log("Generated poolInfosHash:");
        console.logBytes32(poolInfosHash);

        accountant.updatePoolsHash(address(wethPlpVault), poolInfosHash);
        console.log("Pools hash updated");

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("HypoVault Implementation:", hypoVaultImplAddress);
        console.log("Factory:", vaultFactoryAddress);
        console.log("Accountant:", accountantAddress);
        console.log("Vault:", wethPlpVaultAddress);
        console.log("Manager:", managerAddress);
        console.log("DecoderAndSantizer:", collateralTrackerDecoderAndSanitizer);
        console.log("Authority:", authorityAddress);

        // TODO: be mindful msg sender is owner still. transfer ownership if necessary
    }

    function createDefaultPools() internal returns (PanopticVaultAccountant.PoolInfo[] memory) {
        int24 TWAP_TICK = 100;
        int24 MAX_PRICE_DEVIATION = 1700000; // basically no price deviation check for deployment
        uint32 TWAP_WINDOW = 600; // 10 minutes

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
            isUnderlyingToken0InOracle0: true,
            oracle1: oracle1,
            isUnderlyingToken0InOracle1: false,
            maxPriceDeviation: MAX_PRICE_DEVIATION,
            twapWindow: TWAP_WINDOW
        });
        return pools;
    }
}
