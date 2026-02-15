// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "lib/boring-vault/lib/solmate/src/tokens/ERC4626.sol";
import {console} from "forge-std/console.sol";
import {HypoVault} from "../../src/HypoVault.sol";
import {HypoVaultFactory} from "../../src/HypoVaultFactory.sol";
import {IVaultAccountant} from "../../src/interfaces/IVaultAccountant.sol";
import "../../src/accountants/PanopticVaultAccountant.sol";
import {MerkleTreeHelper} from "../../test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {HypoVaultManagerWithMerkleVerification} from "../../src/managers/HypoVaultManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";

contract DeployHypoVault is MerkleTreeHelper {
    // Real Panoptic multisig
    // ISafe PanopticMultisig = ISafe(0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1);
    // @dev - test Safe on sepolia. NOT the real multisig.
    address PanopticMultisig = address(0x9C44C2B07380DA62a5ea572b886048410b0c44fd);

    // Deployment addresses
    address BalancerVaultAddr = address(0x7777); // Required by ManagerWithMerkleVerification

    function deployVault(
        address deployer,
        address vaultFactory,
        address accountantAddress,
        address collateralTrackerDecoderAndSanitizer,
        address authorityAddress,
        address turnkeyAccount,
        address underlyingToken,
        address collateralTracker,
        address panopticPool,
        address weth,
        string memory symbol,
        string memory name,
        bytes32 salt
    )
        internal
        returns (
            address vault,
            address manager,
            ManageLeaf[] memory leafs,
            bytes32[][] memory manageTree
        )
    {
        // 1. Deploy HypoVault via Factory
        uint256 performanceFeeBps = 1000; // 10%
        address vaultAddress = HypoVaultFactory(vaultFactory).createVault(
            underlyingToken,
            deployer,
            IVaultAccountant(accountantAddress),
            performanceFeeBps,
            symbol,
            name,
            salt
        );
        HypoVault vault = HypoVault(payable(vaultAddress));
        console.log("vaultAddress: ", vaultAddress);

        // 2. Set Fee Wallet
        vault.setFeeWallet(turnkeyAccount); // vault level
        console.log("Set fee wallet to:", turnkeyAccount);

        // 3. Deploy HypoVaultManagerWithMerkleVerification with CREATE2
        HypoVaultManagerWithMerkleVerification manager = new HypoVaultManagerWithMerkleVerification{
            salt: salt
        }(deployer, address(vault), BalancerVaultAddr);
        address managerAddress = address(manager);
        console.log("Manager Address:", managerAddress);

        // 4. Set HypoVault manager
        vault.setManager(managerAddress);
        console.log("Manager set on vault");

        // 5. Build merkle tree for manage operations
        setSourceChainName(sepolia);
        setAddress(true, sepolia, "boringVault", address(vault));
        setAddress(true, sepolia, "managerAddress", managerAddress);
        setAddress(true, sepolia, "accountantAddress", accountantAddress);
        setAddress(
            true,
            sepolia,
            "rawDataDecoderAndSanitizer",
            collateralTrackerDecoderAndSanitizer
        );

        ManageLeaf[] memory leafs = new ManageLeaf[](16);
        _addCollateralTrackerLeafs(leafs, ERC4626(collateralTracker), panopticPool, weth);
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        string memory filePath = string.concat(
            "./hypoVaultManagerArtifacts/Production",
            symbol,
            "StrategistLeaves.json"
        );
        _generateLeafs(filePath, leafs, manageRoot, manageTree); // Dump tree and leaves to JSON. Useful for SDK later.

        console.log("Generated manageRoot:");
        console.logBytes32(manageRoot);

        // 6. Set manageRoot for both multisig and turnkey
        manager.setManageRoot(PanopticMultisig, manageRoot);
        manager.setManageRoot(turnkeyAccount, manageRoot); // vault turnkey
        console.log("ManageRoot set for multisig and turnkey");

        // 7. Set RolesAuthority as authority on HypoVaultManagerWithMerkleVerification
        manager.setAuthority(Authority(authorityAddress));
        console.log("Authority set on manager");

        // 8. Grant STRATEGIST_ROLE to TurnkeyAccount0
        uint8 STRATEGIST_ROLE = 7;
        RolesAuthority authority = RolesAuthority(authorityAddress);
        authority.setUserRole(turnkeyAccount, STRATEGIST_ROLE, true); // vault turnkey
        console.log("STRATEGIST_ROLE granted to:", turnkeyAccount);

        // 9. Set abilities/capabilities for STRATEGIST_ROLE
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

        // 10. Update PanopticVaultAccountant pools hash for vault
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createPanopticAccountantPoolInfos();
        _writePoolInfosToJson(address(vault), poolInfos, symbol);
        bytes32 poolInfosHash = keccak256(abi.encode(poolInfos));
        console.log("Generated poolInfosHash:");
        console.logBytes32(poolInfosHash);

        PanopticVaultAccountant(accountantAddress).updatePoolsHash(address(vault), poolInfosHash);
        console.log("Pools hash updated");

        // TODO: Add transfer ownership calls to the multisig

        return (address(vault), address(managerAddress), leafs, manageTree);
    }

    function createPanopticAccountantPoolInfos()
        internal
        pure
        returns (PanopticVaultAccountant.PoolInfo[] memory)
    {
        int24 MAX_PRICE_DEVIATION = 100;

        address token0 = 0x0000000000000000000000000000000000000000; // eth
        address token1 = 0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A; // sepolia mock USDC
        address ethUsdc500bpsV4PanopticPool = 0xA2dCe8f451e311BeFD427e3846BD117687af7B8E;

        PanopticVaultAccountant.PoolInfo[] memory pools = new PanopticVaultAccountant.PoolInfo[](1);
        pools[0] = PanopticVaultAccountant.PoolInfo({
            pool: IPanopticPoolV2(ethUsdc500bpsV4PanopticPool),
            token0: IERC20Partial(token0),
            token1: IERC20Partial(token1),
            maxPriceDeviation: MAX_PRICE_DEVIATION
        });
        return pools;
    }

    function _writePoolInfosToJson(
        address vault,
        PanopticVaultAccountant.PoolInfo[] memory poolInfos,
        string memory symbol
    ) private {
        string memory filePath = string.concat(
            "./hypoVaultManagerArtifacts/Production",
            symbol,
            "VaultPoolInfos.json"
        );
        if (vm.exists(filePath)) {
            vm.removeFile(filePath);
        }

        vm.writeLine(filePath, "{");
        // Write vault address manually - serializeAddress returns a full JSON object, we just need the key-value pair
        vm.writeLine(filePath, string.concat('"vaultAddress":"', vm.toString(vault), '",'));
        vm.writeLine(filePath, '"poolInfos": [');

        for (uint256 i; i < poolInfos.length; ++i) {
            vm.writeLine(filePath, _serializePoolInfo(poolInfos[i]));
            if (i != poolInfos.length - 1) {
                vm.writeLine(filePath, ",");
            }
        }

        vm.writeLine(filePath, "]");
        vm.writeLine(filePath, "}");
    }

    function _serializePoolInfo(
        PanopticVaultAccountant.PoolInfo memory info
    ) private returns (string memory) {
        string memory poolJson = "poolInfo";
        vm.serializeAddress(poolJson, "pool", address(info.pool));
        vm.serializeAddress(poolJson, "token0", address(info.token0));
        vm.serializeAddress(poolJson, "token1", address(info.token1));
        string memory finalJson = vm.serializeInt(
            poolJson,
            "maxPriceDeviation",
            info.maxPriceDeviation
        );
        return finalJson;
    }
}
