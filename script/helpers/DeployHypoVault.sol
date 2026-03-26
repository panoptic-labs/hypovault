// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "lib/boring-vault/lib/solmate/src/tokens/ERC4626.sol";
import {console} from "forge-std/console.sol";
import {HypoVault} from "../../src/HypoVault.sol";
import {HypoVaultFactory} from "../../src/HypoVaultFactory.sol";
import {IVaultAccountant} from "../../src/interfaces/IVaultAccountant.sol";
import "../../src/accountants/PanopticVaultAccountant.sol";
import {MerkleTreeHelper} from "../../test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {IERC20} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Partial} from "lib/panoptic-v2-core/contracts/tokens/interfaces/IERC20Partial.sol";
import "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {HypoVaultManagerWithMerkleVerification} from "../../src/managers/HypoVaultManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";

contract DeployHypoVault is MerkleTreeHelper {
    struct DeployStruct {
        address deployer;
        address vaultFactory;
        address accountantAddress;
        address collateralTrackerDecoderAndSanitizer;
        address authorityAddress;
        address turnkeyAccount;
        address underlyingToken;
        address collateralTracker;
        address panopticPool;
        address weth;
        address token0;
        address token1;
        string chainName;
        string symbol;
        string name;
        bytes32 salt;
    }

    // @dev - test Safe on sepolia. NOT the real multisig.
    // Real Panoptic multisig: 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1
    address constant PanopticMultisig = 0x9C44C2B07380DA62a5ea572b886048410b0c44fd;

    // Deployment addresses
    address BalancerVaultAddr = address(0x7777); // Required by ManagerWithMerkleVerification

    function deployVault(
        DeployStruct memory deployData
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
        vault = HypoVaultFactory(deployData.vaultFactory).createVault(
            deployData.underlyingToken,
            deployData.deployer,
            IVaultAccountant(deployData.accountantAddress),
            performanceFeeBps,
            deployData.symbol,
            deployData.name,
            deployData.salt
        );
        HypoVault _vault = HypoVault(payable(vault));
        console.log("vaultAddress: ", vault);

        // 2. Set Fee Wallet
        _vault.setFeeWallet(deployData.turnkeyAccount); // vault level
        console.log("Set fee wallet to:", deployData.turnkeyAccount);

        // 3. Deploy HypoVaultManagerWithMerkleVerification with CREATE2
        manager = address(
            new HypoVaultManagerWithMerkleVerification{salt: deployData.salt}(
                deployData.deployer,
                vault,
                BalancerVaultAddr
            )
        );
        console.log("Manager Address:", manager);

        // 4. Set HypoVault manager
        _vault.setManager(manager);
        console.log("Manager set on vault");

        // 5-10: Configure manager, merkle tree, roles, and accountant
        (leafs, manageTree) = _configureVault(deployData, vault, manager);
    }

    function _configureVault(
        DeployStruct memory deployData,
        address vaultAddress,
        address managerAddress
    ) internal returns (ManageLeaf[] memory leafs, bytes32[][] memory manageTree) {
        HypoVaultManagerWithMerkleVerification manager = HypoVaultManagerWithMerkleVerification(
            managerAddress
        );

        // 5. Build merkle tree for manage operations
        setSourceChainName(deployData.chainName);
        setAddress(true, deployData.chainName, "boringVault", vaultAddress);
        setAddress(true, deployData.chainName, "managerAddress", managerAddress);
        setAddress(true, deployData.chainName, "accountantAddress", deployData.accountantAddress);
        setAddress(
            true,
            deployData.chainName,
            "rawDataDecoderAndSanitizer",
            deployData.collateralTrackerDecoderAndSanitizer
        );

        bool isPayable = deployData.underlyingToken == deployData.weth;
        leafs = new ManageLeaf[](8);
        _addCollateralTrackerLeafs(
            leafs,
            ERC4626(deployData.collateralTracker),
            deployData.panopticPool,
            deployData.weth,
            isPayable
        );
        manageTree = _generateMerkleTree(leafs);
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        string memory filePath = string.concat(
            "./hypoVaultManagerArtifacts/",
            deployData.chainName,
            "/",
            deployData.symbol,
            "StrategistLeaves.json"
        );
        _generateLeafs(filePath, leafs, manageRoot, manageTree);

        console.log("Generated manageRoot:");
        console.logBytes32(manageRoot);

        // 6. Set manageRoot for both multisig and turnkey
        manager.setManageRoot(PanopticMultisig, manageRoot);
        manager.setManageRoot(deployData.turnkeyAccount, manageRoot);
        console.log("ManageRoot set for multisig and turnkey");

        // 7. Set RolesAuthority as authority on HypoVaultManagerWithMerkleVerification
        manager.setAuthority(Authority(deployData.authorityAddress));
        console.log("Authority set on manager");

        // 8. Grant STRATEGIST_ROLE to TurnkeyAccount0
        _configureRoles(deployData, managerAddress);

        // 10. Update PanopticVaultAccountant hashes for vault
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createPanopticAccountantPoolInfos(
            deployData.panopticPool,
            deployData.token0,
            deployData.token1
        );
        _writePoolInfosToJson(vaultAddress, poolInfos, deployData.symbol, deployData.chainName);
        console.log("Generated poolInfosHash:");
        console.logBytes32(keccak256(abi.encode(poolInfos)));

        PanopticVaultAccountant(deployData.accountantAddress).updateHashes(
            vaultAddress,
            poolInfos,
            new IERC4626[](0)
        );
        console.log("Vault hashes updated");

        // TODO: Add transfer ownership calls to the multisig
    }

    function _configureRoles(DeployStruct memory deployData, address managerAddress) internal {
        uint8 STRATEGIST_ROLE = 7;
        RolesAuthority authority = RolesAuthority(deployData.authorityAddress);
        authority.setUserRole(deployData.turnkeyAccount, STRATEGIST_ROLE, true);
        console.log("STRATEGIST_ROLE granted to:", deployData.turnkeyAccount);

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
    }

    function createPanopticAccountantPoolInfos(
        address panopticPool,
        address token0,
        address token1
    ) internal pure returns (PanopticVaultAccountant.PoolInfo[] memory) {
        int24 MAX_PRICE_DEVIATION = 100;

        PanopticVaultAccountant.PoolInfo[] memory pools = new PanopticVaultAccountant.PoolInfo[](1);
        pools[0] = PanopticVaultAccountant.PoolInfo({
            pool: PanopticPoolV2(panopticPool),
            token0: IERC20Partial(token0),
            token1: IERC20Partial(token1),
            maxPriceDeviation: MAX_PRICE_DEVIATION
        });
        return pools;
    }

    function _writePoolInfosToJson(
        address vault,
        PanopticVaultAccountant.PoolInfo[] memory poolInfos,
        string memory symbol,
        string memory chainName
    ) private {
        string memory filePath = string.concat(
            "./hypoVaultManagerArtifacts/",
            chainName,
            "/",
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
