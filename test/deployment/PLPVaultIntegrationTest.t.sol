// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../src/HypoVault.sol";
import "../../src/HypoVaultFactory.sol";
import "../../src/accountants/PanopticVaultAccountant.sol";
import {CollateralTrackerDecoderAndSanitizer} from "../../src/DecodersAndSanitizers/CollateralTrackerDecoderAndSanitizer.sol";
import {PanopticDecoderAndSanitizer} from "../../src/DecodersAndSanitizers/PanopticDecoderAndSanitizer.sol";
import {ERC20S} from "lib/panoptic-v1.1/test/foundry/testUtils/ERC20S.sol";
import {ERC4626} from "lib/boring-vault/lib/solmate/src/tokens/ERC4626.sol";
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {Math} from "lib/panoptic-v1.1/contracts/libraries/Math.sol";

import {HypoVaultManagerWithMerkleVerification} from "../../src/managers/HypoVaultManagerWithMerkleVerification.sol";
import {ManagerWithMerkleVerification} from "lib/boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
// import {AccessManager} from "lib/boring-vault/lib/openzeppelin-contracts/contracts/access/manager/AccessManager.sol";
import {RolesAuthority, Authority} from "lib/boring-vault/lib/solmate/src/auth/authorities/RolesAuthority.sol";
import {Authority} from "lib/boring-vault/lib/solmate/src/auth/Auth.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {DeployArchitecture} from "../../script/helpers/DeployArchitecture.sol";
import {DeployHypoVault} from "../../script/helpers/DeployHypoVault.sol";

contract VaultAccountantMock {
    uint256 public nav;
    address public expectedVault;
    bytes public expectedManagerInput;

    function setNav(uint256 _nav) external {
        nav = _nav;
    }

    function setExpectedVault(address _expectedVault) external {
        expectedVault = _expectedVault;
    }

    function setExpectedManagerInput(bytes memory _expectedManagerInput) external {
        expectedManagerInput = _expectedManagerInput;
    }

    function computeNAV(
        address vault,
        address,
        bytes memory managerInput
    ) external view returns (uint256) {
        require(vault == expectedVault, "Invalid vault");
        if (managerInput.length > 0) {
            require(
                keccak256(managerInput) == keccak256(expectedManagerInput),
                "Invalid manager input"
            );
        }
        return nav;
    }
}

// Mock contract to test manage function calldata passing
contract MockTarget {
    uint256 public value;
    bytes public lastCalldata;
    address public lastCaller;
    uint256 public lastValue;
    bool public wasCalled;

    function simpleFunction(uint256 _value) external payable {
        value = _value;
        lastCalldata = msg.data;
        lastCaller = msg.sender;
        lastValue = msg.value;
        wasCalled = true;
    }

    function complexFunction(
        uint256 a,
        string memory b,
        address,
        bytes memory
    ) external payable returns (uint256, string memory) {
        value = a;
        lastCalldata = msg.data;
        lastCaller = msg.sender;
        lastValue = msg.value;
        wasCalled = true;
        return (a * 2, string(abi.encodePacked(b, "_modified")));
    }

    function revertingFunction() external pure {
        revert("Test revert");
    }

    function getStoredData() external view returns (uint256, bytes memory, address, uint256, bool) {
        return (value, lastCalldata, lastCaller, lastValue, wasCalled);
    }
}

contract HypoVaultTest is Test, MerkleTreeHelper, DeployArchitecture, DeployHypoVault {
    VaultAccountantMock public accountant;
    HypoVaultFactory public vaultFactory;
    HypoVault public vault;
    ERC20S public token;

    address Manager = address(0x1234);
    address FeeWallet = address(0x5678);
    address Alice = address(0x123456);
    address Bob = address(0x12345678);
    address Charlie = address(0x1234567891);
    address Dave = address(0x12345678912);
    address Eve = address(0x123456789123);

    uint256 constant INITIAL_BALANCE = 1000000 ether;
    uint256 constant BOOTSTRAP_SHARES = 1_000_000;

    // Events
    event WithdrawalRequested(address indexed user, uint256 shares, bool shouldRedeposit);
    event DepositRequested(address indexed user, uint256 amount);
    event RedepositStatusChanged(address indexed user, uint256 indexed epoch, bool shouldRedeposit);

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate expected shares for a deposit
    function calculateExpectedShares(
        uint256 assetsToFulfill,
        uint256 totalAssets,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        return Math.mulDiv(assetsToFulfill, totalSupply, totalAssets);
    }

    /// @notice Calculate expected assets for a withdrawal
    function calculateExpectedAssets(
        uint256 sharesToFulfill,
        uint256 totalAssets,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        return Math.mulDiv(sharesToFulfill, totalAssets, totalSupply);
    }

    /// @notice Calculate expected performance fee
    function calculateExpectedPerformanceFee(
        uint256 assetsToWithdraw,
        uint256 withdrawnBasis
    ) internal view returns (uint256) {
        if (assetsToWithdraw <= withdrawnBasis) return 0;
        return ((assetsToWithdraw - withdrawnBasis) * vault.performanceFeeBps()) / 10_000;
    }

    /// @notice Calculate proportional fulfillment for multiple users
    function calculateProportionalFulfillment(
        uint256 userDeposit,
        uint256 totalDeposits,
        uint256 fulfillAmount
    ) internal pure returns (uint256) {
        return (userDeposit * fulfillAmount) / totalDeposits;
    }

    function setUp() public {
        accountant = new VaultAccountantMock();
        token = new ERC20S("Test Token", "TEST", 18);

        address implementation = address(new HypoVault());

        vaultFactory = new HypoVaultFactory(implementation);

        vault = HypoVault(
            payable(
                vaultFactory.createVault(
                    address(token),
                    Manager,
                    IVaultAccountant(address(accountant)),
                    100,
                    "TEST",
                    "Test Token",
                    keccak256("test-vault-salt")
                )
            )
        );
        accountant.setExpectedVault(address(vault));

        // Set fee wallet
        vm.prank(Manager);
        vault.setFeeWallet(FeeWallet);

        // Mint tokens and approve vault for all users
        address[6] memory users = [Alice, Bob, Charlie, Dave, Eve, Manager];
        for (uint i = 0; i < users.length; i++) {
            token.mint(users[i], INITIAL_BALANCE);
            vm.prank(users[i]);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function test_complete_manager_no_fork_with_panoptic_collateral_integration_flow() public {
        console2.log("=== Step 1: Deploy ===");
        uint256 forkId = vm.createSelectFork(
            string.concat("https://eth-sepolia.g.alchemy.com/v2/", vm.envString("ALCHEMY_API_KEY")),
            9775660
        );

        address PanopticMultisig = 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1;
        address owner = PanopticMultisig;
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
        address BalancerVault = address(0x7777); // Required by ManagerWithMerkleVerification
        ERC20S sepoliaWeth = ERC20S(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
        address wethUsdc500bpsV3Collateral0 = 0x1AF0D98626d53397BA5613873D3b19cc25235d52; // Underlying: WETH9 | 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
        address wethUsdc500bpsV3PanopticPool = 0x00002c1c2EF3E4b606F8361d975Cdc2834668e9F; // Underlying: WETH9 | receives deposited assets

        /*
           STEP 1: Deployments
        */

        vm.startPrank(owner);

        // Deploy core architecture
        bytes32 salt = keccak256("test-vault-salt");
        (
            ,
            address vaultFactory,
            address accountant,
            address panopticDecoderAndSanitizer,
            address authorityAddress
        ) = deployArchitecture(salt, owner);

        // Deploy vault using the helper
        (
            address vaultAddress,
            address managerAddress,
            MerkleTreeHelper.ManageLeaf[] memory leafs,
            bytes32[][] memory manageTree
        ) = deployVault(
                owner,
                vaultFactory,
                accountant,
                panopticDecoderAndSanitizer,
                authorityAddress,
                TurnkeyAccount0,
                address(sepoliaWeth),
                "povLendWETH",
                "Panoptic Lend Vault | WETH",
                salt
            );

        vm.stopPrank();

        // Get references to deployed contracts
        HypoVault wethPlpVault = HypoVault(payable(vaultAddress));
        HypoVaultManagerWithMerkleVerification wethPlpVaultManager = HypoVaultManagerWithMerkleVerification(
                managerAddress
            );
        PanopticVaultAccountant panopticVaultAccountant = PanopticVaultAccountant(accountant);
        RolesAuthority rolesAuthority = RolesAuthority(authorityAddress);

        assertEq(wethPlpVault.manager(), address(wethPlpVaultManager));

        console2.log("=== Step 2: Verify deployment setup ===");
        /*
           STEP 2: Verify that deployVault() set everything up correctly
        */

        // Verify authority is set
        assertEq(address(wethPlpVaultManager.authority()), authorityAddress);

        // Verify Turnkey signer has role and can call manage functions
        uint8 STRATEGIST_ROLE = 7;
        assertTrue(rolesAuthority.doesUserHaveRole(TurnkeyAccount0, STRATEGIST_ROLE));
        assertTrue(
            rolesAuthority.canCall(
                TurnkeyAccount0,
                address(wethPlpVaultManager),
                HypoVaultManagerWithMerkleVerification.fulfillDeposits.selector
            )
        );
        assertTrue(
            rolesAuthority.canCall(
                TurnkeyAccount0,
                address(wethPlpVaultManager),
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            )
        );

        // Verify Turnkey CANNOT update manageRoot
        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        assertNotEq(manageRoot, bytes32(0)); // Verify manageRoot was set
        vm.startPrank(TurnkeyAccount0);
        vm.expectRevert();
        wethPlpVaultManager.setManageRoot(TurnkeyAccount0, manageRoot);
        vm.stopPrank();

        // Verify Owner CAN still update manageRoot
        vm.prank(owner);
        wethPlpVaultManager.setManageRoot(TurnkeyAccount0, manageRoot);

        console2.log("=== Step 3: Test curator can fulfill deposits ===");

        // Alice requests a WETH deposit
        deal(address(sepoliaWeth), Alice, 100 ether);
        vm.startPrank(Alice);
        sepoliaWeth.approve(address(wethPlpVault), type(uint256).max);
        wethPlpVault.requestDeposit(100 ether);
        vm.stopPrank();

        assertGe(sepoliaWeth.balanceOf(address(wethPlpVault)), 100 ether);
        // assumes epoch is 0. may not be the case. should use HypoVault.depositEpoch instead
        assertEq(wethPlpVault.queuedDeposit(Alice, 0), 100 ether);

        // Initialize pools in Accountant that Vault is allowed interact with
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createDefaultPools();
        vm.prank(owner);
        bytes32 poolInfosHash = keccak256(abi.encode(poolInfos));
        panopticVaultAccountant.updatePoolsHash(address(wethPlpVault), poolInfosHash);
        assertEq(panopticVaultAccountant.vaultPools(address(wethPlpVault)), poolInfosHash);

        int24 TWAP_TICK = 100;
        PanopticVaultAccountant.ManagerPrices[]
            memory managerPrices = new PanopticVaultAccountant.ManagerPrices[](1);
        managerPrices[0] = PanopticVaultAccountant.ManagerPrices({
            poolPrice: TWAP_TICK, // token1 to token0 (aka underlyingToken)
            token0Price: 0, // token0 == underlyingToken
            token1Price: TWAP_TICK // token1 to token0 (aka underlyingToken)
        });

        bytes memory managerInput = abi.encode(managerPrices, poolInfos, new TokenId[][](1));
        vm.prank(TurnkeyAccount0);
        wethPlpVaultManager.fulfillDeposits(100 ether, managerInput);

        // Check deposit was fulfilled
        assertEq(wethPlpVault.depositEpoch(), 1);
        (uint128 assetsDeposited, , uint128 assetsFulfilled) = wethPlpVault.depositEpochState(0);
        assertEq(assetsDeposited, 100 ether);
        assertEq(assetsFulfilled, 100 ether);

        console2.log("=== Step 5: Execute deposit and test withdrawals ===");

        wethPlpVault.executeDeposit(Alice, 0);
        uint256 aliceShares = wethPlpVault.balanceOf(Alice);
        assertGt(aliceShares, 0);

        // Alice requests 50% withdrawal
        vm.prank(Alice);
        wethPlpVault.requestWithdrawal(uint128(aliceShares / 2));

        // TurnkeyAccount0 fulfills withdrawals
        vm.prank(TurnkeyAccount0);
        wethPlpVaultManager.fulfillWithdrawals(aliceShares / 2, 50 ether, managerInput);

        // Execute withdrawal
        uint256 aliceBalanceBefore = sepoliaWeth.balanceOf(Alice);
        wethPlpVault.executeWithdrawal(Alice, 0);
        assertGt(sepoliaWeth.balanceOf(Alice), aliceBalanceBefore);

        console2.log(
            "=== Step 6: Test CollateralTracker deposit call with Merkle verification ==="
        );
        // Create call to approve collateral0 to spend sepoliaWeth. Allowed because we set the manage root earlier.
        // Remember targets, targetData, manageProofs (so manageLeafs too), values, decodersAndSanitizers arrays must all be the same length
        address[] memory targets = new address[](2);
        targets[0] = address(sepoliaWeth);
        targets[1] = address(wethUsdc500bpsV3Collateral0);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            ERC20S.approve.selector,
            wethUsdc500bpsV3Collateral0,
            type(uint256).max
        );
        targetData[1] = abi.encodeWithSelector(ERC4626.deposit.selector, 50 ether, wethPlpVault);

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](2);
        // To determine which index of leaf to use, easiest to look at
        // JSON output from _generateLeafs, especially when multiple leafs adding helpers are used (like _addCollateralTrackerLeafs)
        // Note: leafs[0] = fulfillDeposits, leafs[1] = fulfillWithdrawals, leafs[2] = approve, leafs[3] = deposit, etc.
        manageLeafs[0] = leafs[2]; // approve leaf
        manageLeafs[1] = leafs[3]; // deposit leaf
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);
        console.log("got proofs");

        // Log manageLeafs
        for (uint256 i = 0; i < manageLeafs.length; i++) {
            console.log("manageLeafs[%s]:", i);
            logManageLeaf(manageLeafs[i]);
        }

        // Log manageProofs
        for (uint256 i = 0; i < manageTree.length; i++) {
            console.log("manageTree[%s]:", i);
            for (uint256 j = 0; j < manageTree[i].length; j++) {
                console.logBytes32(manageTree[i][j]);
            }
        }

        // Log manageProofs
        for (uint256 i = 0; i < manageProofs.length; i++) {
            console.log("manageProofs[%s]:", i);
            for (uint256 j = 0; j < manageProofs[i].length; j++) {
                console.logBytes32(manageProofs[i][j]);
            }
        }

        // leave values empty since we're not sending native assets
        uint256[] memory values = new uint256[](2);

        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = panopticDecoderAndSanitizer;
        decodersAndSanitizers[1] = panopticDecoderAndSanitizer;

        vm.startPrank(TurnkeyAccount0);
        uint256 initialCollateralWethAllowance = sepoliaWeth.allowance(
            address(wethPlpVault),
            wethUsdc500bpsV3Collateral0
        );
        uint256 initialPPWethBalance = sepoliaWeth.balanceOf(wethUsdc500bpsV3PanopticPool);

        wethPlpVaultManager.manageVaultWithMerkleVerification(
            manageProofs,
            decodersAndSanitizers,
            targets,
            targetData,
            values
        );

        uint256 newCollateralWethAllowance = sepoliaWeth.allowance(
            address(wethPlpVault),
            wethUsdc500bpsV3Collateral0
        );
        uint256 newPPWethBalance = sepoliaWeth.balanceOf(wethUsdc500bpsV3PanopticPool);

        assertGt(newCollateralWethAllowance, initialCollateralWethAllowance);
        assertGt(newPPWethBalance, initialPPWethBalance);

        vm.stopPrank();

        console2.log("=== Integration test completed successfully! ===");
    }

    function test_turnkey_can_manage_vault() public {
        // Used only as example for SDK. Does not need to be run every time.
        vm.skip(true);
        console2.log("=== Init ===");
        uint256 forkId = vm.createSelectFork(
            string.concat("https://eth-sepolia.g.alchemy.com/v2/", vm.envString("ALCHEMY_API_KEY")),
            9775660
        );

        address PanopticMultisig = 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1;
        address owner = 0x7643c4F21661691fb851AfedaF627695672C9fac;
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
        address BalancerVault = address(0x7777); // Required by ManagerWithMerkleVerification
        ERC20S sepoliaWeth = ERC20S(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
        address wethUsdc500bpsV3Collateral0 = 0x1AF0D98626d53397BA5613873D3b19cc25235d52; // Underlying: WETH9 | 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
        address wethUsdc500bpsV3PanopticPool = 0x00002c1c2EF3E4b606F8361d975Cdc2834668e9F; // Underlying: WETH9 | receives deposited assets

        // use contract suite deployed from EOA
        HypoVault wethPlpVault = HypoVault(payable(0x5B61131B0b2589b5C8f6B93C6F989b5dAdFF0FB4));
        HypoVaultManagerWithMerkleVerification wethPlpVaultManager = HypoVaultManagerWithMerkleVerification(
                0x585a97cb89DC2E345D9fb80b84a5038c6D8c8118
            );
        PanopticVaultAccountant panopticVaultAccountant = PanopticVaultAccountant(
            0x425379d80bf1ED904006B3C893BEa1903Fc13caF
        );
        RolesAuthority rolesAuthority = RolesAuthority(0x8d50AB622417Fa699F19bd125E69E927418c4B2A);

        /////////////////////////////
        // rebuild merkle tree to show full manage flow
        ///////////////////////
        address collateralTrackerDecoderAndSanitizer = 0x068C823B047B0cBAEFB1aE57Cf792D05665858b7;
        setSourceChainName(sepolia);
        setAddress(false, sepolia, "boringVault", address(wethPlpVault));
        setAddress(false, sepolia, "managerAddress", address(wethPlpVaultManager));
        setAddress(false, sepolia, "accountantAddress", address(panopticVaultAccountant));
        setAddress(
            false,
            sepolia,
            "rawDataDecoderAndSanitizer",
            collateralTrackerDecoderAndSanitizer
        );

        ManageLeaf[] memory leafs = new ManageLeaf[](8); // limit to smallest power of 2 that is grater than leaf size

        _addCollateralTrackerLeafs(leafs, ERC4626(wethUsdc500bpsV3Collateral0));

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        bytes32 manageRoot = manageTree[manageTree.length - 1][0];
        ////////////////////// end manageroot set up

        // Confirm TurnkeyAccount0 can manage before doing the whole thing
        assertTrue(
            rolesAuthority.canCall(
                TurnkeyAccount0,
                address(wethPlpVaultManager),
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            )
        );

        console2.log("=== Step 4: Test curator can fulfill deposits ===");

        // Alice requests a WETH deposit
        deal(address(sepoliaWeth), Alice, 100 ether);
        vm.startPrank(Alice);
        sepoliaWeth.approve(address(wethPlpVault), type(uint256).max);
        wethPlpVault.requestDeposit(100 ether);
        vm.stopPrank();

        assertGe(sepoliaWeth.balanceOf(address(wethPlpVault)), 100 ether);
        // assumes epoch is 0. may not be the case. should use HypoVault.depositEpoch instead
        assertEq(wethPlpVault.queuedDeposit(Alice, 0), 100 ether);

        // Initialize pools in Accountant that Vault is allowed interact with
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createDefaultPools();
        vm.prank(owner);
        bytes32 poolInfosHash = keccak256(abi.encode(poolInfos));
        panopticVaultAccountant.updatePoolsHash(address(wethPlpVault), poolInfosHash);
        assertEq(panopticVaultAccountant.vaultPools(address(wethPlpVault)), poolInfosHash);

        // Get latest tick to create managerInput
        (
            int24 currentTick,
            int24 fastOracleTick,
            int24 slowOracleTick,
            int24 latestObservation,
            uint256 medianData
        ) = PanopticPool(wethUsdc500bpsV3PanopticPool).getOracleTicks();
        PanopticVaultAccountant.ManagerPrices[]
            memory managerPrices = new PanopticVaultAccountant.ManagerPrices[](1);
        managerPrices[0] = PanopticVaultAccountant.ManagerPrices({
            poolPrice: currentTick, // token1 to token0 (aka underlyingToken)
            token0Price: 0, // token0 == underlyingToken
            token1Price: currentTick // token1 to token0 (aka underlyingToken)
        });

        bytes memory managerInput = abi.encode(managerPrices, poolInfos, new TokenId[][](1));
        vm.prank(TurnkeyAccount0);
        wethPlpVaultManager.fulfillDeposits(100 ether, managerInput);

        // Check deposit was fulfilled
        assertEq(wethPlpVault.depositEpoch(), 1);
        (uint128 assetsDeposited, , uint128 assetsFulfilled) = wethPlpVault.depositEpochState(0);
        assertEq(assetsDeposited, 100 ether);
        assertEq(assetsFulfilled, 100 ether);

        console2.log("=== Step 5: Execute deposit and test withdrawals ===");

        wethPlpVault.executeDeposit(Alice, 0);
        uint256 aliceShares = wethPlpVault.balanceOf(Alice);
        assertGt(aliceShares, 0);

        // Alice requests 50% withdrawal
        vm.prank(Alice);
        wethPlpVault.requestWithdrawal(uint128(aliceShares / 2));

        // TurnkeyAccount0 fulfills withdrawals
        vm.prank(TurnkeyAccount0);
        wethPlpVaultManager.fulfillWithdrawals(aliceShares / 2, 50 ether, managerInput);

        // Execute withdrawal
        uint256 aliceBalanceBefore = sepoliaWeth.balanceOf(Alice);
        wethPlpVault.executeWithdrawal(Alice, 0);
        assertGt(sepoliaWeth.balanceOf(Alice), aliceBalanceBefore);

        console2.log(
            "=== Step 6: Test CollateralTracker deposit call with Merkle verification ==="
        );
        // Create call to approve collateral0 to spend sepoliaWeth. Allowed because we set the manage root earlier.
        // Remember targets, targetData, manageProofs (so manageLeafs too), values, decodersAndSanitizers arrays must all be the same length
        address[] memory targets = new address[](2);
        targets[0] = address(sepoliaWeth);
        targets[1] = address(wethUsdc500bpsV3Collateral0);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            ERC20S.approve.selector,
            wethUsdc500bpsV3Collateral0,
            type(uint256).max
        );
        targetData[1] = abi.encodeWithSelector(ERC4626.deposit.selector, 50 ether, wethPlpVault);

        ManageLeaf[] memory manageLeafs = new ManageLeaf[](2);
        // To determine which index of leaf to use, easiest to look at
        // JSON output from _generateLeafs, especially when multiple leafs adding helpers are used (like _addCollateralTrackerLeafs)
        manageLeafs[0] = leafs[0];
        manageLeafs[1] = leafs[1];
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);
        console.log("got proofs");

        // Log manageLeafs
        for (uint256 i = 0; i < manageLeafs.length; i++) {
            console.log("manageLeafs[%s]:", i);
            logManageLeaf(manageLeafs[i]);
        }

        // Log manageProofs
        for (uint256 i = 0; i < manageTree.length; i++) {
            console.log("manageTree[%s]:", i);
            for (uint256 j = 0; j < manageTree[i].length; j++) {
                console.logBytes32(manageTree[i][j]);
            }
        }

        // Log manageProofs
        for (uint256 i = 0; i < manageProofs.length; i++) {
            console.log("manageProofs[%s]:", i);
            for (uint256 j = 0; j < manageProofs[i].length; j++) {
                console.logBytes32(manageProofs[i][j]);
            }
        }

        // leave values empty since we're not sending native assets
        uint256[] memory values = new uint256[](2);

        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = collateralTrackerDecoderAndSanitizer;
        decodersAndSanitizers[1] = collateralTrackerDecoderAndSanitizer;

        vm.startPrank(TurnkeyAccount0);
        uint256 initialCollateralWethAllowance = sepoliaWeth.allowance(
            address(wethPlpVault),
            wethUsdc500bpsV3Collateral0
        );
        uint256 initialPPWethBalance = sepoliaWeth.balanceOf(wethUsdc500bpsV3PanopticPool);

        wethPlpVaultManager.manageVaultWithMerkleVerification(
            manageProofs,
            decodersAndSanitizers,
            targets,
            targetData,
            values
        );

        uint256 newCollateralWethAllowance = sepoliaWeth.allowance(
            address(wethPlpVault),
            wethUsdc500bpsV3Collateral0
        );
        uint256 newPPWethBalance = sepoliaWeth.balanceOf(wethUsdc500bpsV3PanopticPool);

        assertGt(newCollateralWethAllowance, initialCollateralWethAllowance);
        assertGt(newPPWethBalance, initialPPWethBalance);

        vm.stopPrank();

        console2.log("=== Integration test completed successfully! ===");
    }

    /// @notice Test atomic fulfillDeposits + fund movement via manageVaultWithMerkleVerification
    /// @dev This demonstrates the new atomic flow where fulfillDeposits is the first call in manageVaultWithMerkleVerification
    function test_atomic_fulfillDeposits_and_fund_movement() public {
        console2.log("=== Init: Test atomic fulfillDeposits and fund movement ===");
        uint256 forkId = vm.createSelectFork(
            string.concat("https://eth-sepolia.g.alchemy.com/v2/", vm.envString("ALCHEMY_API_KEY")),
            9775660
        );

        address PanopticMultisig = 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1;
        address owner = PanopticMultisig;
        address TurnkeyAccount0 = address(0x62CB5f6E9F8Bca7032dDf993de8A02ae437D39b8);
        ERC20S sepoliaWeth = ERC20S(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
        address wethUsdc500bpsV3Collateral0 = 0x1AF0D98626d53397BA5613873D3b19cc25235d52;
        address wethUsdc500bpsV3PanopticPool = 0x00002c1c2EF3E4b606F8361d975Cdc2834668e9F;

        /*
           STEP 1: Deployments
        */
        vm.startPrank(owner);

        bytes32 salt = keccak256("test-atomic-vault-salt");
        (
            ,
            address vaultFactory,
            address accountant,
            address panopticDecoderAndSanitizer,
            address authorityAddress
        ) = deployArchitecture(salt, owner);

        (
            address vaultAddress,
            address managerAddress,
            MerkleTreeHelper.ManageLeaf[] memory leafs,
            bytes32[][] memory manageTree
        ) = deployVault(
                owner,
                vaultFactory,
                accountant,
                panopticDecoderAndSanitizer,
                authorityAddress,
                TurnkeyAccount0,
                address(sepoliaWeth),
                "TESTpovLendWETH",
                "Panoptic Lend Vault | WETH",
                salt
            );

        vm.stopPrank();

        HypoVault wethPlpVault = HypoVault(payable(vaultAddress));
        HypoVaultManagerWithMerkleVerification wethPlpVaultManager = HypoVaultManagerWithMerkleVerification(
                managerAddress
            );
        PanopticVaultAccountant panopticVaultAccountant = PanopticVaultAccountant(accountant);

        console2.log("=== Step 2: Alice requests deposit ===");

        deal(address(sepoliaWeth), Alice, 100 ether);
        vm.startPrank(Alice);
        sepoliaWeth.approve(address(wethPlpVault), type(uint256).max);
        wethPlpVault.requestDeposit(100 ether);
        vm.stopPrank();

        assertGe(sepoliaWeth.balanceOf(address(wethPlpVault)), 100 ether);
        assertEq(wethPlpVault.queuedDeposit(Alice, 0), 100 ether);

        // Initialize pools in Accountant
        PanopticVaultAccountant.PoolInfo[] memory poolInfos = createDefaultPools();
        vm.prank(owner);
        bytes32 poolInfosHash = keccak256(abi.encode(poolInfos));
        panopticVaultAccountant.updatePoolsHash(address(wethPlpVault), poolInfosHash);

        console2.log(
            "=== Step 3: Atomic fulfillDeposits + approve + deposit via manageVaultWithMerkleVerification ==="
        );

        // Prepare manager input for fulfillDeposits
        int24 TWAP_TICK = 100;
        PanopticVaultAccountant.ManagerPrices[]
            memory managerPrices = new PanopticVaultAccountant.ManagerPrices[](1);
        managerPrices[0] = PanopticVaultAccountant.ManagerPrices({
            poolPrice: TWAP_TICK,
            token0Price: 0,
            token1Price: TWAP_TICK
        });
        bytes memory managerInput = abi.encode(managerPrices, poolInfos, new TokenId[][](1));

        // Build atomic calls: fulfillDeposits + approve + deposit to CollateralTracker
        address[] memory targets = new address[](3);
        targets[0] = address(wethPlpVaultManager); // Call manager's fulfillDeposits via vault.manage()
        targets[1] = address(sepoliaWeth); // Approve
        targets[2] = address(wethUsdc500bpsV3Collateral0); // Deposit

        bytes[] memory targetData = new bytes[](3);
        targetData[0] = abi.encodeWithSelector(
            HypoVaultManagerWithMerkleVerification.fulfillDeposits.selector,
            100 ether,
            managerInput
        );
        targetData[1] = abi.encodeWithSelector(
            ERC20S.approve.selector,
            wethUsdc500bpsV3Collateral0,
            type(uint256).max
        );
        targetData[2] = abi.encodeWithSelector(ERC4626.deposit.selector, 50 ether, wethPlpVault);

        // Build proofs for all 3 calls
        // leafs[0] = fulfillDeposits, leafs[1] = fulfillWithdrawals, leafs[2] = approve, leafs[3] = deposit
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](3);
        manageLeafs[0] = leafs[0]; // fulfillDeposits
        manageLeafs[1] = leafs[2]; // approve
        manageLeafs[2] = leafs[3]; // deposit
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);

        uint256[] memory values = new uint256[](3);

        address[] memory decodersAndSanitizers = new address[](3);
        decodersAndSanitizers[0] = panopticDecoderAndSanitizer;
        decodersAndSanitizers[1] = panopticDecoderAndSanitizer;
        decodersAndSanitizers[2] = panopticDecoderAndSanitizer;

        // Record initial state
        uint256 initialDepositEpoch = wethPlpVault.depositEpoch();
        uint256 initialCollateralWethAllowance = sepoliaWeth.allowance(
            address(wethPlpVault),
            wethUsdc500bpsV3Collateral0
        );
        uint256 initialPPWethBalance = sepoliaWeth.balanceOf(wethUsdc500bpsV3PanopticPool);

        // Execute atomic operation
        vm.prank(TurnkeyAccount0);
        wethPlpVaultManager.manageVaultWithMerkleVerification(
            manageProofs,
            decodersAndSanitizers,
            targets,
            targetData,
            values
        );

        // Verify fulfillDeposits was executed
        assertEq(
            wethPlpVault.depositEpoch(),
            initialDepositEpoch + 1,
            "Deposit epoch should increment"
        );
        (uint128 assetsDeposited, , uint128 assetsFulfilled) = wethPlpVault.depositEpochState(0);
        assertEq(assetsDeposited, 100 ether, "Assets deposited should match");
        assertEq(assetsFulfilled, 100 ether, "Assets fulfilled should match");

        // Verify approve and deposit were executed
        uint256 newCollateralWethAllowance = sepoliaWeth.allowance(
            address(wethPlpVault),
            wethUsdc500bpsV3Collateral0
        );
        uint256 newPPWethBalance = sepoliaWeth.balanceOf(wethUsdc500bpsV3PanopticPool);

        assertGt(
            newCollateralWethAllowance,
            initialCollateralWethAllowance,
            "Allowance should increase"
        );
        assertGt(newPPWethBalance, initialPPWethBalance, "Panoptic pool balance should increase");

        console2.log("=== Step 4: Verify Alice can execute deposit and get shares ===");

        wethPlpVault.executeDeposit(Alice, 0);
        uint256 aliceShares = wethPlpVault.balanceOf(Alice);
        assertGt(aliceShares, 0, "Alice should have shares");

        console2.log("=== Atomic fulfillDeposits test completed successfully! ===");
    }

    function createDefaultPools() internal returns (PanopticVaultAccountant.PoolInfo[] memory) {
        int24 TWAP_TICK = 100;
        int24 MAX_PRICE_DEVIATION = 1700000; // basically no price deviation check for test
        uint32 TWAP_WINDOW = 600; // 10 minutes
        // With real sepolia oracles
        IV3CompatibleOracle wethUsdc500bpsV3UniswapPool = IV3CompatibleOracle(
            0x1105514b9Eb942F2596A2486093399b59e2F23fC
        );
        IV3CompatibleOracle poolOracle = wethUsdc500bpsV3UniswapPool;
        IV3CompatibleOracle oracle0 = wethUsdc500bpsV3UniswapPool;
        IV3CompatibleOracle oracle1 = wethUsdc500bpsV3UniswapPool;
        // with mock oracles
        // MockV3CompatibleOracle poolOracle;
        // MockV3CompatibleOracle oracle0;
        // MockV3CompatibleOracle oracle1;
        // poolOracle = new MockV3CompatibleOracle();
        // oracle0 = new MockV3CompatibleOracle();
        // oracle1 = new MockV3CompatibleOracle();

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
            isUnderlyingToken0InOracle0: true, // true for WETH vault
            oracle1: oracle1,
            isUnderlyingToken0InOracle1: false,
            maxPriceDeviation: MAX_PRICE_DEVIATION,
            twapWindow: TWAP_WINDOW
        });
        return pools;
    }

    function logManageLeaf(ManageLeaf memory leaf) public pure {
        console2.log("Logging manageLeaf:");
        console2.log("  target: %s", leaf.target);
        console2.log("  canSendValue: %s", leaf.canSendValue);
        console2.log("  signature: %s", leaf.signature);
        if (leaf.argumentAddresses.length == 0) {
            console2.log("  argumentAddresses: []");
        } else {
            for (uint i = 0; i < leaf.argumentAddresses.length; ++i) {
                console2.log("  argumentAddresses[%s]: %s", i, leaf.argumentAddresses[i]);
            }
        }
        console2.log("  description: %s", leaf.description);
        console2.log("  decoderAndSanitizer: %s", leaf.decoderAndSanitizer);
    }
}

contract NoopDecoder {
    fallback() external {
        // Return empty bytes, ABI-encoded as a single dynamic bytes (offset=0x20, length=0)
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x20) // offset to data
            mstore(add(ptr, 0x20), 0) // length of bytes (0)
            return(ptr, 0x40) // return 64 bytes total
        }
    }
}

contract MockERC1155 {
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    function balanceOf(address account, uint256 id) public view returns (uint256) {
        return _balances[id][account];
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory) public {
        _balances[id][to] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public {
        require(from == msg.sender || isApprovedForAll(from, msg.sender), "Not approved");
        require(_balances[id][from] >= amount, "Insufficient balance");

        _balances[id][from] -= amount;
        _balances[id][to] += amount;

        emit TransferSingle(msg.sender, from, to, id, amount);

        _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public {
        require(from == msg.sender || isApprovedForAll(from, msg.sender), "Not approved");
        require(ids.length == amounts.length, "Arrays length mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            require(_balances[id][from] >= amount, "Insufficient balance");

            _balances[id][from] -= amount;
            _balances[id][to] += amount;
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        _doBatchSafeTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function _doBatchSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.code.length > 0) {
            try
                IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data)
            returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }
}

interface IERC1155Receiver {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

contract MockERC721 {
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) public view returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }

    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "Approval to current owner");
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not approved");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function mint(address to, uint256 tokenId) public {
        require(to != address(0), "Mint to zero address");
        require(_owners[tokenId] == address(0), "Token already minted");

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _safeTransfer(from, to, tokenId, data);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Transfer from incorrect owner");
        require(to != address(0), "Transfer to zero address");

        // Clear approvals from the previous owner
        _tokenApprovals[tokenId] = address(0);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, data),
            "Transfer to non ERC721Receiver implementer"
        );
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (
                bytes4 retval
            ) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("Transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// Mock token that doesn't implement decimals() properly
contract MockTokenWithoutDecimals {
    string public name = "Bad Token";
    string public symbol = "BAD";
    uint256 public totalSupply = 1000000;
    mapping(address => uint256) public balanceOf;

    // Intentionally not implementing decimals() function to test fallback behavior
}

contract MockV3CompatibleOracle is IV3CompatibleOracle {
    int56[] public tickCumulatives;
    uint160[] public sqrtPriceX96s;
    uint32 public windowSize;
    int24 public currentTick;
    uint160 public currentSqrtPriceX96;
    uint16 public currentObservationCardinality;

    constructor() {
        // Default tick cumulatives for a 20-slot observation
        for (uint i = 0; i < 20; i++) {
            tickCumulatives.push(int56(int256(1000 + i * 100))); // Increasing tick cumulatives
        }
        windowSize = 600; // 10 minutes
        currentTick = 100;
        currentSqrtPriceX96 = Math.getSqrtRatioAtTick(currentTick);
        currentObservationCardinality = 20;
    }

    function observe(
        uint32[] memory secondsAgos
    ) external view override returns (int56[] memory, uint160[] memory) {
        int56[] memory ticks = new int56[](secondsAgos.length);
        uint160[] memory prices = new uint160[](secondsAgos.length);

        for (uint i = 0; i < secondsAgos.length; i++) {
            if (i < tickCumulatives.length) {
                ticks[i] = tickCumulatives[i];
            } else {
                ticks[i] = tickCumulatives[tickCumulatives.length - 1];
            }
            prices[i] = Math.getSqrtRatioAtTick(int24(ticks[i] / 100));
        }

        return (ticks, prices);
    }

    function slot0()
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (
            currentSqrtPriceX96,
            currentTick,
            0,
            currentObservationCardinality,
            currentObservationCardinality,
            0,
            true
        );
    }

    function observations(
        uint256
    )
        external
        view
        override
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        return (uint32(block.timestamp), 0, 0, true);
    }

    function increaseObservationCardinalityNext(uint16) external override {
        // Mock implementation - do nothing
    }

    function setTickCumulatives(int56[] memory _tickCumulatives) external {
        delete tickCumulatives;
        for (uint i = 0; i < _tickCumulatives.length; i++) {
            tickCumulatives.push(_tickCumulatives[i]);
        }
    }

    function setObservation(uint256 index, int56 tickCumulative, uint160 sqrtPriceX96) external {
        if (index >= tickCumulatives.length) {
            for (uint i = tickCumulatives.length; i <= index; i++) {
                tickCumulatives.push(0);
                sqrtPriceX96s.push(0);
            }
        }
        tickCumulatives[index] = tickCumulative;
        sqrtPriceX96s[index] = sqrtPriceX96;
    }

    function setCurrentState(
        int24 tick,
        uint160 sqrtPriceX96,
        uint16 observationCardinality
    ) external {
        currentTick = tick;
        currentSqrtPriceX96 = sqrtPriceX96;
        currentObservationCardinality = observationCardinality;
    }
}
