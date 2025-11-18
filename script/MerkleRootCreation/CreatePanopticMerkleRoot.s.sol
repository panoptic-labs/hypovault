// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21;

import {FixedPointMathLib} from "lib/boring-vault/lib/solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "lib/boring-vault/lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "lib/boring-vault/lib/solmate/src/tokens/ERC4626.sol";
import {ManagerWithMerkleVerification} from "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "lib/boring-vault/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";

/**
 *  source .env && forge script script/MerkleRootCreation/Mainnet/CreateTestMerkleRoot.s.sol --rpc-url $SEPOLIA_RPC_URL
 */
contract CreatePanopticMerkleRoot is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    address public hypoVault = 0x9f64DAB456351BF1488F7A02190BB532979721A7;
    // panoptic Vault multisig address: 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1
    address public managerAddress = 0x7643c4F21661691fb851AfedaF627695672C9fac; // luis sepolia dev wallet
    address public accountantAddress = 0x09CdD3f95BfB6879065ce18d1d95A6db07b987D7;

    address public collateralTrackerDecoderAndSanitizer =
        0xdc7E264392a851860B5c42c629222c3839C62B24;
    ERC4626 public wethUsdc500bpsV3Collateral0 =
        ERC4626(0x1AF0D98626d53397BA5613873D3b19cc25235d52); // Underlying: WETH9 | 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14

    // address public wethUsdc500bpsV3Collateral1 = 0x0A9a8e10e6D9601b1eE056D194c77D5a2dE40F77; // Underlying: USDC | 0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A

    function setUp() external {}

    /**
     * @notice Uncomment which script you want to run.
     */
    function run() external {
        generateTestStrategistMerkleRoot();
    }

    function generateTestStrategistMerkleRoot() public {
        setSourceChainName(sepolia);
        setAddress(false, sepolia, "boringVault", hypoVault);
        setAddress(false, sepolia, "managerAddress", managerAddress);
        setAddress(false, sepolia, "accountantAddress", accountantAddress);
        setAddress(
            false,
            sepolia,
            "rawDataDecoderAndSanitizer",
            collateralTrackerDecoderAndSanitizer
        );

        ManageLeaf[] memory leafs = new ManageLeaf[](8); // limit to smallest power of 2 that is grater than leaf size >

        _addCollateralTrackerLeafs(leafs, wethUsdc500bpsV3Collateral0);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // Can set root like this as long as script runner has the ability to:
        // manager.setManageRoot(address(this), manageTree[1][0]);

        string memory filePath = "./leafs/PanopticPLPStrategistLeaves.json";

        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);
    }
}
