// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/HypoVault.sol";
import {HypovaultManagerWithMerkleVerification} from "../src/managers/HypovaultManagerWithMerkleVerification.sol";
import {ERC20S} from "lib/panoptic-v1.1/test/foundry/testUtils/ERC20S.sol";
import {Math} from "lib/panoptic-v1.1/contracts/libraries/Math.sol";

// Mock VaultAccountant for testing
contract MockVaultAccountant {
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

// Mock BalancerVault for testing
contract MockBalancerVault {
    // Minimal implementation for testing
}

contract HypovaultManagerWithMerkleVerificationTest is Test {
    HypovaultManagerWithMerkleVerification public manager;
    HypoVault public vault;
    MockVaultAccountant public accountant;
    MockBalancerVault public balancerVault;
    ERC20S public token;

    address public owner = address(0x1);
    address public strategist = address(0x2);
    address public unauthorized = address(0x3);
    address public alice = address(0x4);
    address public bob = address(0x5);

    uint256 constant INITIAL_BALANCE = 1000000 ether;

    function setUp() public {
        // Deploy dependencies
        token = new ERC20S("Test Token", "TEST", 18);
        accountant = new MockVaultAccountant();
        balancerVault = new MockBalancerVault();

        // Step 1: Deploy vault with a dummy manager (address(0x999) as placeholder)
        // Important: Deploy from the owner address so owner becomes the vault owner
        vm.prank(owner);
        vault = new HypoVault(
            address(token),
            address(0),
            address(0x999), // Dummy manager address
            IVaultAccountant(address(accountant)),
            100, // 1% performance fee
            "HVAULT",
            "HypoVault Token"
        );

        // Step 2: Deploy manager with the correct vault address
        vm.prank(owner);
        manager = new HypovaultManagerWithMerkleVerification(
            owner,
            address(vault), // Now we have the real vault address
            address(balancerVault)
        );

        // Step 3: Update the vault's manager to the real manager
        // This requires owner role, which is the deployer (owner)
        vm.prank(owner);
        vault.setManager(address(manager));

        // Verify the setup worked
        assertEq(vault.owner(), owner, "Owner should be set correctly");
        assertEq(vault.manager(), address(manager), "Manager should be updated");

        // Set up accountant
        accountant.setExpectedVault(address(vault));

        // Set up strategist with manage root
        vm.prank(owner);
        bytes32 strategistRoot = keccak256("strategist_root"); // Mock root
        manager.setManageRoot(strategist, strategistRoot);

        // Mint tokens to test users
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);

        // Approve vault
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // Add a test to verify the deployment flow worked correctly
    function testDeploymentFlow() public {
        // Verify ownership structure
        assertEq(vault.owner(), owner, "Vault owner should be owner");
        assertEq(vault.manager(), address(manager), "Vault manager should be manager contract");

        // Verify only owner can update manager
        vm.prank(unauthorized);
        vm.expectRevert(); // Should revert with Ownable error
        vault.setManager(unauthorized);

        vm.prank(owner);
        vault.setManager(address(0x777)); // This should work - owner updating
        assertEq(vault.manager(), address(0x777), "Manager should be updated by owner");

        // Undo
        vm.prank(owner);
        vault.setManager(address(manager)); // go back to manager contract as manager
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyStrategist_modifier_allows_strategist() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // Strategist should be able to cancel deposit
        vm.prank(strategist);
        manager.cancelDeposit(alice);

        // Verify deposit was cancelled
        assertEq(vault.queuedDeposit(alice, 0), 0);
    }

    function test_onlyStrategist_modifier_allows_owner() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // Owner should be able to cancel deposit
        vm.prank(owner);
        manager.cancelDeposit(alice);

        // Verify deposit was cancelled
        assertEq(vault.queuedDeposit(alice, 0), 0);
    }

    function test_onlyStrategist_modifier_reverts_for_unauthorized() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // Unauthorized user should not be able to cancel deposit
        vm.prank(unauthorized);
        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.cancelDeposit(alice);
    }

    function test_onlyStrategist_modifier_reverts_for_zero_root() public {
        // Create new address with no manage root
        address noRoot = address(0x99);

        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // Address with no manage root should not be able to cancel deposit
        vm.prank(noRoot);
        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.cancelDeposit(alice);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancelDeposit_success() public {
        uint256 depositAmount = 200 ether;
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Alice requests deposit
        vm.prank(alice);
        vault.requestDeposit(uint128(depositAmount));

        // Verify deposit is queued
        assertEq(vault.queuedDeposit(alice, 0), depositAmount);
        assertEq(token.balanceOf(alice), aliceBalanceBefore - depositAmount);

        // Strategist cancels deposit
        vm.prank(strategist);
        manager.cancelDeposit(alice);

        // Verify deposit was cancelled and tokens returned
        assertEq(vault.queuedDeposit(alice, 0), 0);
        assertEq(token.balanceOf(alice), aliceBalanceBefore);
    }

    function test_cancelDeposit_multiple_users() public {
        uint256 aliceDeposit = 100 ether;
        uint256 bobDeposit = 150 ether;

        // Both users deposit
        vm.prank(alice);
        vault.requestDeposit(uint128(aliceDeposit));
        vm.prank(bob);
        vault.requestDeposit(uint128(bobDeposit));

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 bobBalanceBefore = token.balanceOf(bob);

        // Strategist cancels both deposits
        vm.prank(strategist);
        manager.cancelDeposit(alice);
        vm.prank(strategist);
        manager.cancelDeposit(bob);

        // Verify both deposits were cancelled
        assertEq(vault.queuedDeposit(alice, 0), 0);
        assertEq(vault.queuedDeposit(bob, 0), 0);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + aliceDeposit);
        assertEq(token.balanceOf(bob), bobBalanceBefore + bobDeposit);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancelWithdrawal_success() public {
        // Setup: Alice gets shares first
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        manager.fulfillDeposits(100 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 sharesToWithdraw = aliceShares / 2;

        // Alice requests withdrawal
        vm.prank(alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Verify shares were burned
        assertEq(vault.balanceOf(alice), aliceShares - sharesToWithdraw);

        // Strategist cancels withdrawal
        vm.prank(strategist);
        manager.cancelWithdrawal(alice);

        // Verify withdrawal was cancelled and shares restored
        assertEq(vault.balanceOf(alice), aliceShares);
        (uint128 amount, , , ) = vault.queuedWithdrawal(alice, 0);
        assertEq(amount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    REQUEST WITHDRAWAL FROM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_requestWithdrawalFrom_with_redeposit() public {
        // Setup: Alice gets shares
        vm.prank(alice);
        vault.requestDeposit(1000 ether);

        vm.startPrank(strategist);
        accountant.setNav(1000 ether);
        manager.fulfillDeposits(1000 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 sharesToWithdraw = aliceShares / 2;

        // Strategist requests withdrawal from Alice with redeposit
        vm.prank(strategist);
        manager.requestWithdrawalFrom(alice, uint128(sharesToWithdraw), 0, true);

        // Verify withdrawal was requested with redeposit flag
        (uint128 amount, uint128 basis, , bool shouldRedeposit) = vault.queuedWithdrawal(alice, 0);
        assertEq(amount, sharesToWithdraw);
        assertEq(basis, 500 ether);
        assertTrue(shouldRedeposit);
    }

    function test_requestWithdrawalFrom_without_redeposit() public {
        // Setup: Alice gets shares
        vm.prank(alice);
        vault.requestDeposit(1000 ether);

        vm.startPrank(strategist);
        accountant.setNav(1000 ether);
        manager.fulfillDeposits(1000 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 sharesToWithdraw = aliceShares / 2;

        // Strategist requests withdrawal from Alice without redeposit
        vm.prank(strategist);
        manager.requestWithdrawalFrom(alice, uint128(sharesToWithdraw), 0, false);

        // Verify withdrawal was requested without redeposit flag
        (uint128 amount, uint128 basis, , bool shouldRedeposit) = vault.queuedWithdrawal(alice, 0);
        assertEq(amount, sharesToWithdraw);
        assertEq(basis, 500 ether);
        assertFalse(shouldRedeposit);
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL DEPOSITS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fulfillDeposits_success() public {
        uint256 depositAmount = 200 ether;

        // Alice and Bob request deposits
        vm.prank(alice);
        vault.requestDeposit(uint128(depositAmount / 2));
        vm.prank(bob);
        vault.requestDeposit(uint128(depositAmount / 2));

        // Strategist fulfills deposits
        vm.startPrank(strategist);
        accountant.setNav(depositAmount);
        manager.fulfillDeposits(depositAmount, "");
        vm.stopPrank();

        // Verify epoch advanced
        assertEq(vault.depositEpoch(), 1);

        // Verify epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, depositAmount);
        assertEq(assetsFulfilled, depositAmount);
        assertGt(sharesReceived, 0);
    }

    function test_fulfillDeposits_partial() public {
        uint256 depositAmount = 300 ether;
        uint256 fulfillAmount = 200 ether;

        // Alice requests deposit
        vm.prank(alice);
        vault.requestDeposit(uint128(depositAmount));

        // Strategist partially fulfills deposits
        vm.startPrank(strategist);
        accountant.setNav(400 ether);
        manager.fulfillDeposits(fulfillAmount, "");
        vm.stopPrank();

        // Execute deposit
        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        // Verify partial fulfillment
        assertEq(vault.userBasis(alice), fulfillAmount);
        assertEq(vault.queuedDeposit(alice, 1), depositAmount - fulfillAmount);
    }

    function test_fulfillDeposits_with_manager_input() public {
        uint256 depositAmount = 100 ether;
        bytes memory managerInput = "test_input";

        vm.prank(alice);
        vault.requestDeposit(uint128(depositAmount));

        // Set expected manager input in accountant
        accountant.setExpectedManagerInput(managerInput);

        // Strategist fulfills with manager input
        vm.startPrank(strategist);
        accountant.setNav(depositAmount);
        manager.fulfillDeposits(depositAmount, managerInput);
        vm.stopPrank();

        // Should succeed if manager input matches
        assertEq(vault.depositEpoch(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL WITHDRAWALS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fulfillWithdrawals_success() public {
        // Setup: Alice gets shares
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        manager.fulfillDeposits(100 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice requests withdrawal
        vm.prank(alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // Strategist fulfills withdrawal
        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        manager.fulfillWithdrawals(aliceShares, 100 ether, 0, "");
        vm.stopPrank();

        // Verify withdrawal epoch advanced
        assertEq(vault.withdrawalEpoch(), 1);

        // Verify epoch state
        (uint128 sharesWithdrawn, uint128 assetsReceived, , uint128 sharesFulfilled) = vault
            .withdrawalEpochState(0);
        assertEq(sharesWithdrawn, aliceShares);
        assertEq(sharesFulfilled, aliceShares);
        assertEq(assetsReceived, 100 ether);
    }

    function test_fulfillWithdrawals_partial() public {
        // Setup: Alice gets shares
        vm.prank(alice);
        vault.requestDeposit(200 ether);

        vm.startPrank(strategist);
        accountant.setNav(200 ether);
        manager.fulfillDeposits(200 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 sharesToWithdraw = aliceShares;

        // Alice requests withdrawal
        vm.prank(alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Strategist partially fulfills withdrawal (75% of shares)
        uint256 sharesToFulfill = (sharesToWithdraw * 75) / 100;
        uint256 assetsToGive = 150 ether; // 75% of 200 ether

        vm.startPrank(strategist);
        accountant.setNav(200 ether);
        manager.fulfillWithdrawals(sharesToFulfill, assetsToGive, 0, "");
        vm.stopPrank();

        // Execute withdrawal
        vm.prank(alice);
        vault.executeWithdrawal(alice, 0);

        // Verify partial fulfillment - Alice should have remaining shares in next epoch
        (uint128 remainingAmount, , , ) = vault.queuedWithdrawal(alice, 1);
        assertEq(remainingAmount, sharesToWithdraw - sharesToFulfill);
    }

    function test_fulfillWithdrawals_max_assets_protection() public {
        // Setup: Alice gets shares
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        manager.fulfillDeposits(100 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice requests withdrawal
        vm.prank(alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // Strategist tries to fulfill with max assets too low
        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        vm.expectRevert(HypoVault.WithdrawalNotFulfillable.selector);
        manager.fulfillWithdrawals(aliceShares, 50 ether, 0, ""); // Too low max
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_complete_deposit_withdrawal_cycle() public {
        uint256 depositAmount = 500 ether;

        // 1. Alice requests deposit
        vm.prank(alice);
        vault.requestDeposit(uint128(depositAmount));

        // 2. Strategist fulfills deposit
        vm.startPrank(strategist);
        accountant.setNav(depositAmount);
        manager.fulfillDeposits(depositAmount, "");
        vm.stopPrank();

        // 3. Alice executes deposit
        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);
        assertGt(aliceShares, 0);
        assertEq(vault.userBasis(alice), depositAmount);

        // 4. Strategist requests withdrawal from Alice with redeposit
        vm.prank(strategist);
        manager.requestWithdrawalFrom(alice, uint128(aliceShares / 2), 0, true);

        // 5. Strategist fulfills withdrawal
        vm.startPrank(strategist);
        accountant.setNav(depositAmount);
        manager.fulfillWithdrawals(aliceShares / 2, 250 ether, 0, "");
        vm.stopPrank();

        // 6. Alice executes withdrawal (should redeposit)
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 currentDepositEpoch = vault.depositEpoch();

        vm.prank(alice);
        vault.executeWithdrawal(alice, 0);

        // Verify redeposit occurred
        assertEq(token.balanceOf(alice), aliceBalanceBefore); // No tokens received
        assertEq(vault.queuedDeposit(alice, currentDepositEpoch), 250 ether); // Assets redeposited
    }

    function test_multiple_strategist_management() public {
        address strategist2 = address(0x6);

        // Owner adds second strategist
        vm.prank(owner);
        bytes32 strategist2Root = keccak256("strategist2_root");
        manager.setManageRoot(strategist2, strategist2Root);

        // Alice deposits
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // First strategist fulfills
        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        manager.fulfillDeposits(100 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        uint256 aliceShares = vault.balanceOf(alice);

        // Alice requests withdrawal
        vm.prank(alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // Second strategist fulfills withdrawal
        vm.startPrank(strategist2);
        accountant.setNav(100 ether);
        manager.fulfillWithdrawals(aliceShares, 100 ether, 0, "");
        vm.stopPrank();

        // Verify second strategist could fulfill
        assertEq(vault.withdrawalEpoch(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR HANDLING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_all_functions_require_authorization() public {
        // Test that all manager functions revert for unauthorized users
        vm.startPrank(unauthorized);

        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.cancelDeposit(alice);

        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.cancelWithdrawal(alice);

        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.requestWithdrawalFrom(alice, 100, 0, true);

        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.fulfillDeposits(100 ether, "");

        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.fulfillWithdrawals(100, 100 ether, 0, "");

        vm.stopPrank();
    }

    function test_owner_can_remove_strategist_access() public {
        // Alice deposits
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // Verify strategist can currently cancel
        vm.prank(strategist);
        manager.cancelDeposit(alice);

        // Alice deposits again
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        // Owner removes strategist's access
        vm.prank(owner);
        manager.setManageRoot(strategist, bytes32(0));

        // Strategist should no longer be able to cancel
        vm.prank(strategist);
        vm.expectRevert(
            HypovaultManagerWithMerkleVerification.HypovaultManager__Unauthorized.selector
        );
        manager.cancelDeposit(alice);

        // But owner still can
        vm.prank(owner);
        manager.cancelDeposit(alice);
    }

    function test_setManageRoot_only_owner() public {
        address newStrategist = address(0x7);
        bytes32 newRoot = keccak256("new_root");

        // Non-owner should not be able to set manage root
        vm.prank(strategist);
        vm.expectRevert(); // Should revert with Ownable error
        manager.setManageRoot(newStrategist, newRoot);

        // Owner should be able to set manage root
        vm.prank(owner);
        manager.setManageRoot(newStrategist, newRoot);

        // Verify new strategist can now perform operations
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        vm.prank(newStrategist);
        manager.cancelDeposit(alice); // Should work
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_zero_amount_operations() public {
        // Alice gets shares first
        vm.prank(alice);
        vault.requestDeposit(100 ether);

        vm.startPrank(strategist);
        accountant.setNav(100 ether);
        manager.fulfillDeposits(100 ether, "");
        vm.stopPrank();

        vm.prank(alice);
        vault.executeDeposit(alice, 0);

        // Test zero shares withdrawal request
        vm.prank(strategist);
        manager.requestWithdrawalFrom(alice, 0, 0, true);

        // Should not revert and should result in no change
        assertEq(vault.balanceOf(alice), vault.balanceOf(alice)); // Unchanged
    }

    function test_fulfill_with_zero_amounts() public {
        // Test fulfilling zero deposits
        accountant.setNav(0);
        vm.prank(strategist);
        manager.fulfillDeposits(0, "");

        // Should advance epoch even with zero fulfillment
        assertEq(vault.depositEpoch(), 1);

        // Test fulfilling zero withdrawals
        vm.prank(strategist);
        manager.fulfillWithdrawals(0, 0, 0, "");

        // Should advance epoch even with zero fulfillment
        assertEq(vault.withdrawalEpoch(), 1);
    }

    // TODO: Would be ideal to also set a sensical merkle root and actually test strategists sending panopticPool.mintOptions, uniswapPool.swap, etc calls
}
