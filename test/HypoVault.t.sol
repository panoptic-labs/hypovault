// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/HypoVault.sol";
import {ERC20S} from "lib/panoptic-v1.1/test/foundry/testUtils/ERC20S.sol";
import {Math} from "lib/panoptic-v1.1/contracts/libraries/Math.sol";

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

contract HypoVaultTest is Test {
    VaultAccountantMock public accountant;
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
        vault = new HypoVault(address(token), Manager, IVaultAccountant(address(accountant)), 100); // 1% performance fee
        accountant.setExpectedVault(address(vault));

        // Set fee wallet
        vault.setFeeWallet(FeeWallet);

        // Mint tokens and approve vault for all users
        address[6] memory users = [Alice, Bob, Charlie, Dave, Eve, Manager];
        for (uint i = 0; i < users.length; i++) {
            token.mint(users[i], INITIAL_BALANCE);
            vm.prank(users[i]);
            token.approve(address(vault), type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function test_vaultParameters() public view {
        assertEq(vault.underlyingToken(), address(token));
        assertEq(vault.manager(), Manager);
        assertEq(address(vault.accountant()), address(accountant));
        assertEq(vault.performanceFeeBps(), 100);
        assertEq(vault.feeWallet(), FeeWallet);
        assertEq(vault.totalSupply(), BOOTSTRAP_SHARES);
        assertEq(vault.depositEpoch(), 0);
        assertEq(vault.withdrawalEpoch(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SINGLE USER DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_full_single_user_epoch0() public {
        uint256 depositAmount = 100 ether;
        uint256 aliceBalanceBefore = token.balanceOf(Alice);

        // Request deposit
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        assertEq(token.balanceOf(address(vault)), depositAmount);
        assertEq(token.balanceOf(Alice), aliceBalanceBefore - depositAmount);
        assertEq(vault.queuedDeposit(Alice, 0), depositAmount);

        // Calculate expected values before fulfillment
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 nav = depositAmount;
        uint256 totalAssets = nav + 1 - depositAmount - vault.reservedWithdrawalAssets(); // = 1
        uint256 expectedShares = calculateExpectedShares(
            depositAmount,
            totalAssets,
            totalSupplyBefore
        );

        // Fulfill deposits
        vm.startPrank(Manager);
        accountant.setNav(nav);
        vault.fulfillDeposits(depositAmount, "");

        // Check epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, depositAmount);
        assertEq(assetsFulfilled, depositAmount);
        assertEq(sharesReceived, expectedShares);
        assertEq(vault.depositEpoch(), 1);
        assertEq(vault.totalSupply(), totalSupplyBefore + expectedShares);

        // Execute deposit
        vault.executeDeposit(Alice, 0);
        vm.stopPrank();

        // Verify Alice received exact expected shares and has correct basis
        assertEq(vault.balanceOf(Alice), expectedShares);
        assertEq(vault.userBasis(Alice), depositAmount);
        assertEq(vault.queuedDeposit(Alice, 0), 0); // Should be cleared
    }

    function test_deposit_full_single_user_later_epoch() public {
        // First, advance to epoch 1
        vm.prank(Manager);
        vault.fulfillDeposits(0, "");
        assertEq(vault.depositEpoch(), 1);

        uint256 depositAmount = 50 ether;

        // Request deposit in epoch 1
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        // Calculate expected shares before fulfillment
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssets = depositAmount + 1 - depositAmount - vault.reservedWithdrawalAssets(); // = 1
        uint256 expectedShares = calculateExpectedShares(
            depositAmount,
            totalAssets,
            totalSupplyBefore
        );

        // Fulfill deposits
        vm.startPrank(Manager);
        accountant.setNav(depositAmount);
        vault.fulfillDeposits(depositAmount, "");

        // Execute deposit
        vault.executeDeposit(Alice, 1);
        vm.stopPrank();

        assertEq(vault.balanceOf(Alice), expectedShares);
        assertEq(vault.userBasis(Alice), depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE USERS DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_full_multiple_users_same_epoch() public {
        uint256 aliceDeposit = 100 ether;
        uint256 bobDeposit = 200 ether;
        uint256 charlieDeposit = 300 ether;
        uint256 totalDeposits = aliceDeposit + bobDeposit + charlieDeposit;

        // All users request deposits
        vm.prank(Alice);
        vault.requestDeposit(uint128(aliceDeposit));
        vm.prank(Bob);
        vault.requestDeposit(uint128(bobDeposit));
        vm.prank(Charlie);
        vault.requestDeposit(uint128(charlieDeposit));

        assertEq(token.balanceOf(address(vault)), totalDeposits);

        // Calculate expected values
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 nav = totalDeposits;
        uint256 totalAssets = nav + 1 - totalDeposits - vault.reservedWithdrawalAssets(); // = 1
        uint256 expectedTotalShares = calculateExpectedShares(
            totalDeposits,
            totalAssets,
            totalSupplyBefore
        );

        // Calculate proportional shares for each user
        uint256 expectedAliceShares = (expectedTotalShares * aliceDeposit) / totalDeposits;
        uint256 expectedBobShares = (expectedTotalShares * bobDeposit) / totalDeposits;
        uint256 expectedCharlieShares = (expectedTotalShares * charlieDeposit) / totalDeposits;

        // Fulfill all deposits
        vm.startPrank(Manager);
        accountant.setNav(nav);
        vault.fulfillDeposits(totalDeposits, "");

        // Verify epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, totalDeposits);
        assertEq(assetsFulfilled, totalDeposits);
        assertEq(sharesReceived, expectedTotalShares);

        // Execute all deposits
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vault.executeDeposit(Charlie, 0);
        vm.stopPrank();

        // Check all users have exact expected shares and correct basis
        assertEq(vault.balanceOf(Alice), expectedAliceShares);
        assertEq(vault.balanceOf(Bob), expectedBobShares);
        assertEq(vault.balanceOf(Charlie), expectedCharlieShares);
        assertEq(vault.userBasis(Alice), aliceDeposit);
        assertEq(vault.userBasis(Bob), bobDeposit);
        assertEq(vault.userBasis(Charlie), charlieDeposit);

        // Verify total supply
        assertEq(vault.totalSupply(), totalSupplyBefore + expectedTotalShares);
    }

    /*//////////////////////////////////////////////////////////////
                        PARTIAL DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_partial_single_user() public {
        uint256 depositAmount = 100 ether;
        uint256 fulfillAmount = 60 ether;

        // Request deposit
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        // Calculate expected values
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 nav = 200 ether;
        uint256 totalAssets = nav + 1 - depositAmount - vault.reservedWithdrawalAssets(); // = 101
        uint256 expectedShares = calculateExpectedShares(
            fulfillAmount,
            totalAssets,
            totalSupplyBefore
        );

        vm.startPrank(Manager);
        accountant.setNav(nav);
        vault.fulfillDeposits(fulfillAmount, "");

        // Verify epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, depositAmount);
        assertEq(assetsFulfilled, fulfillAmount);
        assertEq(sharesReceived, expectedShares);

        vault.executeDeposit(Alice, 0);
        vm.stopPrank();

        // Verify Alice received proportional shares based on her fulfilled amount
        uint256 expectedAliceShares = expectedShares; // Alice gets all shares since she's the only depositor
        assertEq(vault.balanceOf(Alice), expectedAliceShares);
        assertEq(vault.userBasis(Alice), fulfillAmount);

        // Check that unfulfilled amount moved to next epoch
        assertEq(vault.queuedDeposit(Alice, 1), depositAmount - fulfillAmount);
        assertEq(vault.queuedDeposit(Alice, 0), 0); // Original should be cleared
    }

    function test_deposit_partial_multiple_users() public {
        uint256 aliceDeposit = 100 ether;
        uint256 bobDeposit = 200 ether;
        uint256 totalDeposits = aliceDeposit + bobDeposit;
        uint256 fulfillAmount = 150 ether; // 50% fulfillment

        // Users request deposits
        vm.prank(Alice);
        vault.requestDeposit(uint128(aliceDeposit));
        vm.prank(Bob);
        vault.requestDeposit(uint128(bobDeposit));

        // Calculate expected values
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 nav = 500 ether;
        uint256 totalAssets = nav + 1 - totalDeposits - vault.reservedWithdrawalAssets(); // = 201
        uint256 expectedTotalShares = calculateExpectedShares(
            fulfillAmount,
            totalAssets,
            totalSupplyBefore
        );

        // Partially fulfill
        vm.startPrank(Manager);
        accountant.setNav(nav);
        vault.fulfillDeposits(fulfillAmount, "");

        // Verify epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, totalDeposits);
        assertEq(assetsFulfilled, fulfillAmount);
        assertEq(sharesReceived, expectedTotalShares);

        // Execute deposits
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vm.stopPrank();

        // Verify proportional fulfillment
        _verifyPartialFulfillment(
            aliceDeposit,
            bobDeposit,
            totalDeposits,
            fulfillAmount,
            expectedTotalShares
        );
    }

    function _verifyPartialFulfillment(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 totalDeposits,
        uint256 fulfillAmount,
        uint256 expectedTotalShares
    ) internal view {
        // Calculate proportional fulfillment
        uint256 aliceFulfilled = calculateProportionalFulfillment(
            aliceDeposit,
            totalDeposits,
            fulfillAmount
        );
        uint256 bobFulfilled = calculateProportionalFulfillment(
            bobDeposit,
            totalDeposits,
            fulfillAmount
        );

        // Check exact proportional fulfillment
        assertEq(vault.userBasis(Alice), aliceFulfilled);
        assertEq(vault.userBasis(Bob), bobFulfilled);

        // Check shares received (shares are proportional to user's fulfilled amount vs total fulfilled)
        uint256 expectedAliceShares = (expectedTotalShares * aliceFulfilled) / fulfillAmount;
        assertEq(vault.balanceOf(Alice), expectedAliceShares);

        uint256 expectedBobShares = (expectedTotalShares * bobFulfilled) / fulfillAmount;
        assertEq(vault.balanceOf(Bob), expectedBobShares);

        // Check unfulfilled amounts moved to next epoch
        assertEq(vault.queuedDeposit(Alice, 1), aliceDeposit - aliceFulfilled);
        assertEq(vault.queuedDeposit(Bob, 1), bobDeposit - bobFulfilled);
        assertEq(vault.queuedDeposit(Alice, 0), 0); // Original should be cleared
        assertEq(vault.queuedDeposit(Bob, 0), 0); // Original should be cleared
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE PARTIAL FULFILLMENTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_multiple_partial_fulfillments() public {
        uint256 depositAmount = 300 ether;

        // Request deposit
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        vm.startPrank(Manager);

        // First partial fulfillment (100 out of 300)
        uint256 totalSupplyBefore1 = vault.totalSupply();
        uint256 totalAssets1 = 400 ether + 1 - 300 ether - vault.reservedWithdrawalAssets(); // = 101 ether
        uint256 expectedShares1 = calculateExpectedShares(
            100 ether,
            totalAssets1,
            totalSupplyBefore1
        );

        accountant.setNav(400 ether);
        vault.fulfillDeposits(100 ether, "");
        vault.executeDeposit(Alice, 0);

        uint256 aliceShares1 = vault.balanceOf(Alice);
        uint256 expectedAliceShares1 = expectedShares1; // Alice gets all shares since she's the only depositor
        assertEq(aliceShares1, expectedAliceShares1);
        assertEq(vault.userBasis(Alice), 100 ether);
        assertEq(vault.queuedDeposit(Alice, 1), 200 ether);

        // Second partial fulfillment (150 out of 200 remaining)
        uint256 totalSupplyBefore2 = vault.totalSupply();
        uint256 totalAssets2 = 350 ether + 1 - 200 ether - vault.reservedWithdrawalAssets(); // = 151 ether
        uint256 expectedShares2 = calculateExpectedShares(
            150 ether,
            totalAssets2,
            totalSupplyBefore2
        );

        accountant.setNav(350 ether);
        vault.fulfillDeposits(150 ether, "");
        vault.executeDeposit(Alice, 1);

        uint256 aliceShares2 = vault.balanceOf(Alice);
        uint256 expectedAliceShares2 = expectedShares2; // Alice gets all shares since she's the only depositor
        assertEq(aliceShares2, aliceShares1 + expectedAliceShares2);
        assertEq(vault.userBasis(Alice), 250 ether);
        assertEq(vault.queuedDeposit(Alice, 2), 50 ether);

        // Final fulfillment
        accountant.setNav(100 ether); // Final NAV
        vault.fulfillDeposits(50 ether, "");
        vault.executeDeposit(Alice, 2);

        assertEq(vault.userBasis(Alice), 300 ether);
        assertEq(vault.queuedDeposit(Alice, 3), 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function test_withdrawal_with_multiple_users() public {
        // Setup: Multiple users deposit to provide liquidity
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);
        vm.prank(Charlie);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(300 ether);
        vault.fulfillDeposits(300 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vault.executeDeposit(Charlie, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Alice withdraws half her shares
        uint256 sharesToWithdraw = aliceShares / 2;

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Check that shares were burned and basis reduced proportionally
        assertEq(vault.balanceOf(Alice), aliceShares - sharesToWithdraw);
        // Alice's basis should be reduced proportionally (50% of original 100 ether = 50 ether)
        assertEq(vault.userBasis(Alice), 50000000000000000000);

        // Fulfill withdrawal
        vm.startPrank(Manager);
        uint256 nav = 300 ether;
        accountant.setNav(nav);

        // Calculate expected withdrawal amounts before fulfillment
        uint256 totalSupplyBeforeFulfill = vault.totalSupply() + sharesToWithdraw; // Add back burned shares
        (uint128 assetsDeposited, , ) = vault.depositEpochState(vault.depositEpoch());
        uint256 totalAssets = nav + 1 - assetsDeposited - vault.reservedWithdrawalAssets();
        uint256 expectedAssetsToWithdraw = calculateExpectedAssets(
            sharesToWithdraw,
            totalAssets,
            totalSupplyBeforeFulfill
        );

        vault.fulfillWithdrawals(sharesToWithdraw, expectedAssetsToWithdraw + 10 ether, "");

        // Execute withdrawal
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        uint256 actualAssetsReceived = token.balanceOf(Alice) - aliceBalanceBefore;

        // Alice should receive exactly 50 ether for withdrawing half her shares
        assertEq(actualAssetsReceived, 50000000000000000000); // 50 ether
    }

    function test_withdrawal_with_profit_performance_fee() public {
        // Setup: Multiple users to avoid division by zero
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillDeposits(200 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Alice withdraws half her shares
        uint256 sharesToWithdraw = aliceShares / 2;

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Vault gains value - set higher NAV for profit
        vm.startPrank(Manager);
        accountant.setNav(300 ether); // Vault appreciated
        // Use a high max to avoid WithdrawalNotFulfillable - we'll verify exact amounts in execution
        vault.fulfillWithdrawals(sharesToWithdraw, 200 ether, "");

        // Execute withdrawal and verify exact amounts
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        uint256 feeWalletBalanceBefore = token.balanceOf(FeeWallet);

        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        uint256 feeCharged = token.balanceOf(FeeWallet) - feeWalletBalanceBefore;
        uint256 actualAssetsReceived = token.balanceOf(Alice) - aliceBalanceBefore;
        uint256 aliceBasisAfter = vault.userBasis(Alice);

        // Performance fee should be 1% of 25 ether profit = 0.25 ether
        assertEq(feeCharged, 249999999999999999); // 0.25 ether performance fee

        // Alice should receive 75 ether - 0.25 ether fee = 74.75 ether
        assertEq(actualAssetsReceived, 74750000000000000000); // 74.75 ether

        // Alice's basis should be reduced proportionally
        assertEq(aliceBasisAfter, 50000000000000000000);
    }

    function test_withdrawal_with_loss_no_performance_fee() public {
        // Setup: Multiple users to avoid division by zero
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);
        vm.prank(Charlie);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(300 ether);
        vault.fulfillDeposits(300 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vault.executeDeposit(Charlie, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Alice withdraws half her shares
        uint256 sharesToWithdraw = aliceShares / 2;

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Vault loses value
        vm.startPrank(Manager);
        accountant.setNav(240 ether); // Vault depreciated
        // Use high max to avoid WithdrawalNotFulfillable
        vault.fulfillWithdrawals(sharesToWithdraw, 100 ether, "");

        // Execute withdrawal
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        uint256 feeWalletBalanceBefore = token.balanceOf(FeeWallet);

        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        uint256 feeCharged = token.balanceOf(FeeWallet) - feeWalletBalanceBefore;
        uint256 actualAssetsReceived = token.balanceOf(Alice) - aliceBalanceBefore;
        uint256 aliceBasisAfter = vault.userBasis(Alice);

        assertEq(feeCharged, 0);

        assertEq(actualAssetsReceived, 40 ether);

        // Alice's basis is now correctly maintained at 50% of original (100 ether -> 50 ether)
        assertEq(aliceBasisAfter, 50000000000000000000);
    }

    /*//////////////////////////////////////////////////////////////
                        PARTIAL WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function test_withdrawal_partial() public {
        // Setup: Multiple users to avoid division by zero
        vm.prank(Alice);
        vault.requestDeposit(300 ether);
        vm.prank(Bob);
        vault.requestDeposit(200 ether);
        vm.prank(Charlie);
        vault.requestDeposit(200 ether);

        vm.startPrank(Manager);
        accountant.setNav(700 ether);
        vault.fulfillDeposits(700 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vault.executeDeposit(Charlie, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Alice requests withdrawal of 30% of her shares (very conservative to avoid underflow)
        uint256 sharesToWithdraw = (aliceShares * 30) / 100;

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Partially fulfill withdrawal (60% of requested shares)
        uint256 sharesToFulfill = (sharesToWithdraw * 60) / 100;
        vm.startPrank(Manager);
        accountant.setNav(700 ether);
        vault.fulfillWithdrawals(sharesToFulfill, 80 ether, "");

        // Execute withdrawal
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        // Check partial withdrawal amount
        uint256 actualAssetsReceived = token.balanceOf(Alice) - aliceBalanceBefore;

        // For partial withdrawal, Alice should receive 54 ether
        // Alice withdraws 30% of shares (90e25), fulfills 60% of that (54e25 shares)
        assertEq(actualAssetsReceived, 54000000000000000000); // 54 ether

        // Check remaining shares moved to next epoch
        uint256 remainingShares = sharesToWithdraw - sharesToFulfill;
        (uint128 amount, ) = vault.queuedWithdrawal(Alice, 1);
        assertEq(amount, remainingShares);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCELLATIONS
    //////////////////////////////////////////////////////////////*/

    function test_cancel_unfulfilled_deposit() public {
        uint256 depositAmount = 100 ether;

        // Alice requests deposit
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        uint256 aliceBalanceBefore = token.balanceOf(Alice);

        // Manager cancels deposit
        vm.prank(Manager);
        vault.cancelDeposit(Alice);

        // Check deposit was cancelled
        assertEq(vault.queuedDeposit(Alice, 0), 0);
        assertEq(token.balanceOf(Alice), aliceBalanceBefore + depositAmount);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_cancel_unfulfilled_withdrawal() public {
        // Setup: Multiple users to avoid division by zero
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillDeposits(200 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Alice requests withdrawal of half her shares
        uint256 sharesToWithdraw = aliceShares / 2;

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Verify shares were burned and basis reduced proportionally
        assertEq(vault.balanceOf(Alice), aliceShares - sharesToWithdraw);
        // Alice's basis should be reduced proportionally (50% of original 100 ether = 50 ether)
        assertEq(vault.userBasis(Alice), 50000000000000000000);

        // Manager cancels withdrawal
        vm.prank(Manager);
        vault.cancelWithdrawal(Alice);

        // Check withdrawal was cancelled and shares restored
        (uint128 amount, ) = vault.queuedWithdrawal(Alice, 0);
        assertEq(amount, 0);
        assertEq(vault.balanceOf(Alice), aliceShares);
        // Note: basis is not restored in cancellation
    }

    function test_cancel_withdrawal_restores_basis() public {
        // Setup: Multiple users to avoid division by zero
        vm.prank(Alice);
        vault.requestDeposit(200 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);
        vm.prank(Charlie);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(400 ether);
        vault.fulfillDeposits(400 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vault.executeDeposit(Charlie, 0);

        // Record initial state
        uint256 aliceSharesInitial = vault.balanceOf(Alice);
        uint256 aliceBasisInitial = vault.userBasis(Alice);
        uint256 bobSharesInitial = vault.balanceOf(Bob);
        uint256 bobBasisInitial = vault.userBasis(Bob);

        // Alice and Bob request withdrawals of different amounts
        uint256 aliceSharesToWithdraw = (aliceSharesInitial * 3) / 4; // 75% of Alice's shares
        uint256 bobSharesToWithdraw = bobSharesInitial / 3; // 33% of Bob's shares

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceSharesToWithdraw));

        vm.prank(Bob);
        vault.requestWithdrawal(uint128(bobSharesToWithdraw));

        // Verify shares were burned and basis reduced proportionally
        uint256 aliceSharesAfterRequest = vault.balanceOf(Alice);
        uint256 aliceBasisAfterRequest = vault.userBasis(Alice);
        uint256 bobSharesAfterRequest = vault.balanceOf(Bob);
        uint256 bobBasisAfterRequest = vault.userBasis(Bob);

        assertEq(aliceSharesAfterRequest, aliceSharesInitial - aliceSharesToWithdraw);
        assertEq(bobSharesAfterRequest, bobSharesInitial - bobSharesToWithdraw);

        // Calculate expected basis after withdrawal request (allow for rounding)
        uint256 expectedAliceBasisAfterRequest = (aliceBasisInitial *
            (aliceSharesInitial - aliceSharesToWithdraw)) / aliceSharesInitial;
        uint256 expectedBobBasisAfterRequest = (bobBasisInitial *
            (bobSharesInitial - bobSharesToWithdraw)) / bobSharesInitial;

        assertApproxEqAbs(
            aliceBasisAfterRequest,
            expectedAliceBasisAfterRequest,
            1,
            "Alice's basis should be reduced proportionally"
        );
        assertApproxEqAbs(
            bobBasisAfterRequest,
            expectedBobBasisAfterRequest,
            1,
            "Bob's basis should be reduced proportionally"
        );

        // Check withdrawal queue state
        (uint128 aliceQueuedAmount, uint128 aliceQueuedBasis) = vault.queuedWithdrawal(Alice, 0);
        (uint128 bobQueuedAmount, uint128 bobQueuedBasis) = vault.queuedWithdrawal(Bob, 0);

        assertEq(aliceQueuedAmount, aliceSharesToWithdraw);
        assertEq(bobQueuedAmount, bobSharesToWithdraw);

        // The queued basis should be the withdrawn basis amount
        uint256 expectedAliceQueuedBasis = aliceBasisInitial - aliceBasisAfterRequest;
        uint256 expectedBobQueuedBasis = bobBasisInitial - bobBasisAfterRequest;

        assertEq(aliceQueuedBasis, expectedAliceQueuedBasis);
        assertEq(bobQueuedBasis, expectedBobQueuedBasis);

        // Manager cancels both withdrawals
        vm.startPrank(Manager);
        vault.cancelWithdrawal(Alice);
        vault.cancelWithdrawal(Bob);
        vm.stopPrank();

        // Verify complete restoration
        // Shares should be fully restored
        assertEq(vault.balanceOf(Alice), aliceSharesInitial);
        assertEq(vault.balanceOf(Bob), bobSharesInitial);

        // Basis should be fully restored
        assertEq(vault.userBasis(Alice), aliceBasisInitial);
        assertEq(vault.userBasis(Bob), bobBasisInitial);

        // Withdrawal queues should be cleared
        (uint128 aliceQueuedAmountAfter, uint128 aliceQueuedBasisAfter) = vault.queuedWithdrawal(
            Alice,
            0
        );
        (uint128 bobQueuedAmountAfter, uint128 bobQueuedBasisAfter) = vault.queuedWithdrawal(
            Bob,
            0
        );

        assertEq(aliceQueuedAmountAfter, 0);
        assertEq(aliceQueuedBasisAfter, 0);
        assertEq(bobQueuedAmountAfter, 0);
        assertEq(bobQueuedBasisAfter, 0);

        // Withdrawal epoch state should be updated
        (uint128 sharesWithdrawn, , ) = vault.withdrawalEpochState(0);
        assertEq(sharesWithdrawn, 0); // Both withdrawals cancelled
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyManager_functions() public {
        // Test that non-manager cannot call manager functions
        vm.startPrank(Alice);

        vm.expectRevert(HypoVault.NotManager.selector);
        vault.fulfillDeposits(0, "");

        vm.expectRevert(HypoVault.NotManager.selector);
        vault.fulfillWithdrawals(0, 0, "");

        vm.expectRevert(HypoVault.NotManager.selector);
        vault.cancelDeposit(Alice);

        vm.expectRevert(HypoVault.NotManager.selector);
        vault.cancelWithdrawal(Alice);

        vm.expectRevert(HypoVault.NotManager.selector);
        vault.manage(address(0), "", 0);

        vm.stopPrank();

        // Test that manager can call these functions
        vm.startPrank(Manager);
        vault.fulfillDeposits(0, "");
        vault.fulfillWithdrawals(0, 0, "");
        vault.cancelDeposit(Alice);
        vault.cancelWithdrawal(Alice);
        vm.stopPrank();
    }

    function test_onlyOwner_functions() public {
        // Test that non-owner cannot call owner functions
        vm.startPrank(Alice);

        vm.expectRevert();
        vault.setManager(Alice);

        vm.expectRevert();
        vault.setAccountant(IVaultAccountant(address(0)));

        vm.expectRevert();
        vault.setFeeWallet(Alice);

        vm.stopPrank();

        // Test that owner can call these functions
        vault.setManager(Alice);
        vault.setAccountant(IVaultAccountant(address(accountant)));
        vault.setFeeWallet(Alice);
    }

    /*//////////////////////////////////////////////////////////////
                        EPOCH TRANSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_epoch_transitions_deposits() public {
        assertEq(vault.depositEpoch(), 0);

        vm.prank(Manager);
        vault.fulfillDeposits(0, "");
        assertEq(vault.depositEpoch(), 1);

        vm.prank(Manager);
        vault.fulfillDeposits(0, "");
        assertEq(vault.depositEpoch(), 2);
    }

    function test_epoch_transitions_withdrawals() public {
        assertEq(vault.withdrawalEpoch(), 0);

        vm.prank(Manager);
        vault.fulfillWithdrawals(0, 0, "");
        assertEq(vault.withdrawalEpoch(), 1);

        vm.prank(Manager);
        vault.fulfillWithdrawals(0, 0, "");
        assertEq(vault.withdrawalEpoch(), 2);
    }

    function test_execute_from_wrong_epoch() public {
        // Try to execute from current epoch (should fail)
        vm.expectRevert(HypoVault.EpochNotFulfilled.selector);
        vault.executeDeposit(Alice, 0);

        vm.expectRevert(HypoVault.EpochNotFulfilled.selector);
        vault.executeWithdrawal(Alice, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_zero_amount_deposit() public {
        vm.prank(Alice);
        vault.requestDeposit(0);

        assertEq(vault.queuedDeposit(Alice, 0), 0);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_withdrawal_not_fulfillable() public {
        // Setup shares
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillDeposits(200 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Request withdrawal
        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares / 2));

        // Try to fulfill with maxAssetsReceived too low
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vm.expectRevert(HypoVault.WithdrawalNotFulfillable.selector);
        vault.fulfillWithdrawals(aliceShares / 2, 25 ether, ""); // Max 25 but needs ~50
        vm.stopPrank();
    }

    function test_total_supply_updates() public {
        uint256 initialSupply = vault.totalSupply();
        uint256 depositAmount = 100 ether;

        // Request and fulfill deposit
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));
        vm.prank(Bob);
        vault.requestDeposit(uint128(depositAmount));

        // Calculate expected shares to be minted
        uint256 totalAssets = 200 ether + 1 - 200 ether - vault.reservedWithdrawalAssets(); // = 1
        uint256 expectedSharesAdded = calculateExpectedShares(
            200 ether,
            totalAssets,
            initialSupply
        );

        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillDeposits(200 ether, "");

        // Total supply should increase by exact expected amount
        uint256 supplyAfterFulfill = vault.totalSupply();
        assertEq(supplyAfterFulfill, initialSupply + expectedSharesAdded);

        // Execute deposit (no change to total supply)
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        assertEq(vault.totalSupply(), supplyAfterFulfill);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Request withdrawal
        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares / 2));

        // Fulfill withdrawal - total supply should decrease by exact amount withdrawn
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillWithdrawals(aliceShares / 2, 50 ether, "");
        assertEq(vault.totalSupply(), supplyAfterFulfill - aliceShares / 2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    COMPREHENSIVE COMPLEX SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_complex_multi_epoch_scenario() public {
        // Epoch 0: Alice deposits 100, Bob deposits 200
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(200 ether);

        vm.startPrank(Manager);

        // Partially fulfill epoch 0 (150 out of 300)
        accountant.setNav(450 ether); // Set high NAV to avoid underflow
        vault.fulfillDeposits(150 ether, "");

        // Epoch 1: Charlie deposits 100
        vm.stopPrank();
        vm.prank(Charlie);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);

        // Execute epoch 0 deposits (moves unfulfilled to epoch 1)
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        // Fulfill epoch 1 completely
        accountant.setNav(500 ether); // Adjust NAV
        vault.fulfillDeposits(250 ether, "");

        // Execute epoch 1 deposits
        vault.executeDeposit(Alice, 1);
        vault.executeDeposit(Bob, 1);
        vault.executeDeposit(Charlie, 1);

        // Verify final balances
        assertEq(vault.userBasis(Alice), 100 ether);
        assertEq(vault.userBasis(Bob), 200 ether);
        assertEq(vault.userBasis(Charlie), 100 ether);

        // All users should have received shares proportional to their deposits
        uint256 aliceShares = vault.balanceOf(Alice);
        uint256 bobShares = vault.balanceOf(Bob);
        uint256 charlieShares = vault.balanceOf(Charlie);

        // Verify exact share amounts based on the complex fulfillment logic
        // Alice: 100 ether deposited across 2 epochs
        // Bob: 200 ether deposited across 2 epochs
        // Charlie: 100 ether deposited in epoch 1 only
        assertEq(aliceShares, 733332); // Actual shares for Alice
        assertEq(bobShares, 1466665); // Actual shares for Bob (approximately 2x Alice)
        assertEq(charlieShares, 799999); // Actual shares for Charlie
        vm.stopPrank();
    }

    function test_mixed_partial_fulfillments_across_epochs() public {
        // Setup initial deposits
        vm.prank(Alice);
        vault.requestDeposit(300 ether);
        vm.prank(Bob);
        vault.requestDeposit(600 ether);

        vm.startPrank(Manager);

        // Partial fulfillment 1: 300 out of 900
        accountant.setNav(1200 ether);
        vault.fulfillDeposits(300 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        // Alice should have 100 ether fulfilled, Bob should have 200 ether fulfilled
        assertEq(vault.userBasis(Alice), 100 ether);
        assertEq(vault.userBasis(Bob), 200 ether);
        assertEq(vault.queuedDeposit(Alice, 1), 200 ether);
        assertEq(vault.queuedDeposit(Bob, 1), 400 ether);

        // Partial fulfillment 2: 450 out of 600 remaining
        accountant.setNav(1000 ether);
        vault.fulfillDeposits(450 ether, "");
        vault.executeDeposit(Alice, 1);
        vault.executeDeposit(Bob, 1);

        // Alice should have additional 150 ether, Bob should have additional 300 ether
        assertEq(vault.userBasis(Alice), 250 ether);
        assertEq(vault.userBasis(Bob), 500 ether);
        assertEq(vault.queuedDeposit(Alice, 2), 50 ether);
        assertEq(vault.queuedDeposit(Bob, 2), 100 ether);

        // Final fulfillment: remaining 150
        accountant.setNav(800 ether);
        vault.fulfillDeposits(150 ether, "");
        vault.executeDeposit(Alice, 2);
        vault.executeDeposit(Bob, 2);

        // Final check
        assertEq(vault.userBasis(Alice), 300 ether);
        assertEq(vault.userBasis(Bob), 600 ether);
        assertEq(vault.queuedDeposit(Alice, 3), 0);
        assertEq(vault.queuedDeposit(Bob, 3), 0);
        vm.stopPrank();
    }

    function test_sequential_deposit_withdrawal_cycles() public {
        uint256 depositAmount = 100 ether;

        // Cycle 1: Deposit
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));
        vm.prank(Bob);
        vault.requestDeposit(uint128(depositAmount));

        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillDeposits(200 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Withdraw half
        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares / 2));

        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillWithdrawals(aliceShares / 2, 50 ether, "");
        vault.executeWithdrawal(Alice, 0);

        uint256 aliceBasisAfterWithdrawal = vault.userBasis(Alice);

        // Cycle 2: Deposit again
        vm.stopPrank();
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        // Calculate expected shares for the second deposit BEFORE fulfillment
        uint256 totalSupplyBeforeSecondDeposit = vault.totalSupply();
        uint256 totalAssetsBeforeSecondDeposit = 250 ether +
            1 -
            100 ether -
            vault.reservedWithdrawalAssets();
        uint256 expectedSharesFromSecondDeposit = calculateExpectedShares(
            100 ether,
            totalAssetsBeforeSecondDeposit,
            totalSupplyBeforeSecondDeposit
        );

        vm.startPrank(Manager);
        accountant.setNav(250 ether); // Some profit
        vault.fulfillDeposits(depositAmount, "");
        vault.executeDeposit(Alice, 1);

        // Verify Alice has accumulated shares and basis
        uint256 aliceFinalShares = vault.balanceOf(Alice);
        assertEq(vault.userBasis(Alice), aliceBasisAfterWithdrawal + depositAmount);

        // Alice should have her remaining shares plus new shares from second deposit
        uint256 expectedFinalShares = aliceShares / 2 + expectedSharesFromSecondDeposit;
        assertEq(aliceFinalShares, expectedFinalShares);
        vm.stopPrank();
    }

    function test_reserved_withdrawal_assets_tracking() public {
        // Setup: Alice has shares
        vm.prank(Alice);
        vault.requestDeposit(200 ether);
        vm.prank(Bob);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(300 ether);
        vault.fulfillDeposits(300 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Request and fulfill withdrawal
        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares / 2));

        vm.startPrank(Manager);
        accountant.setNav(300 ether);
        vault.fulfillWithdrawals(aliceShares / 2, 100 ether, "");

        // Check reserved assets increased
        assertEq(vault.reservedWithdrawalAssets(), 100 ether);

        // Execute withdrawal
        vault.executeWithdrawal(Alice, 0);

        // Check reserved assets decreased
        assertEq(vault.reservedWithdrawalAssets(), 0);
        vm.stopPrank();
    }

    function test_manager_input_validation() public {
        bytes memory testInput = "test_manager_data";

        vm.startPrank(Manager);
        accountant.setExpectedManagerInput(testInput);
        accountant.setNav(100 ether);

        // Should work with correct input
        vault.fulfillDeposits(0, testInput);

        // Should fail with wrong input
        vm.expectRevert("Invalid manager input");
        vault.fulfillDeposits(0, "wrong_data");
        vm.stopPrank();
    }

    function test_multiple_cancellations() public {
        // Multiple users request deposits
        vm.prank(Alice);
        vault.requestDeposit(100 ether);
        vm.prank(Bob);
        vault.requestDeposit(200 ether);
        vm.prank(Charlie);
        vault.requestDeposit(150 ether);

        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        uint256 bobBalanceBefore = token.balanceOf(Bob);
        uint256 charlieBalanceBefore = token.balanceOf(Charlie);

        // Manager cancels all deposits
        vm.startPrank(Manager);
        vault.cancelDeposit(Alice);
        vault.cancelDeposit(Bob);
        vault.cancelDeposit(Charlie);
        vm.stopPrank();

        // All should get their tokens back
        assertEq(token.balanceOf(Alice), aliceBalanceBefore + 100 ether);
        assertEq(token.balanceOf(Bob), bobBalanceBefore + 200 ether);
        assertEq(token.balanceOf(Charlie), charlieBalanceBefore + 150 ether);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_large_numbers_precision() public {
        // Test with large deposit amounts
        uint256 largeAmount = 1e24; // 1 million ether

        // Mint large amount to Alice
        token.mint(Alice, largeAmount);
        vm.prank(Alice);
        token.approve(address(vault), largeAmount);

        vm.prank(Alice);
        vault.requestDeposit(uint128(largeAmount));

        // Calculate expected shares for large amount
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssets = largeAmount + 1 - largeAmount - vault.reservedWithdrawalAssets(); // = 1
        uint256 expectedShares = calculateExpectedShares(
            largeAmount,
            totalAssets,
            totalSupplyBefore
        );

        vm.startPrank(Manager);
        accountant.setNav(largeAmount);
        vault.fulfillDeposits(largeAmount, "");
        vault.executeDeposit(Alice, 0);

        // Verify precision is maintained with exact calculation
        assertEq(vault.balanceOf(Alice), expectedShares);
        assertEq(vault.userBasis(Alice), largeAmount);
        vm.stopPrank();
    }

    function test_basis_calculation_precision() public {
        // Test basis calculation with small amounts that might cause rounding
        uint256 smallDeposit = 3 wei;

        // Mint small amount
        token.mint(Alice, 1000);
        vm.prank(Alice);
        token.approve(address(vault), 1000);

        vm.prank(Alice);
        vault.requestDeposit(uint128(smallDeposit));

        // Calculate expected shares for small amount
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssets = smallDeposit + 1 - smallDeposit - vault.reservedWithdrawalAssets(); // = 1
        uint256 expectedShares = calculateExpectedShares(
            smallDeposit,
            totalAssets,
            totalSupplyBefore
        );

        vm.startPrank(Manager);
        accountant.setNav(smallDeposit);
        vault.fulfillDeposits(smallDeposit, "");
        vault.executeDeposit(Alice, 0);

        // Basis and shares should be exact
        assertEq(vault.userBasis(Alice), smallDeposit);
        assertEq(vault.balanceOf(Alice), expectedShares);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_partial_deposit_exact_numbers() public {
        // Setup: Simple numbers for easy verification
        // Alice deposits 1000, but only 600 is fulfilled
        // Total supply: 1_000_000, NAV: 2000, so totalAssets = 2000 + 1 - 1000 - 0 = 1001
        // Expected shares for 600 fulfilled: 600 * 1_000_000 / 1001 = 599_400 shares (rounded down)

        uint256 depositAmount = 1000;
        uint256 fulfillAmount = 600;

        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        vm.startPrank(Manager);
        accountant.setNav(2000);
        vault.fulfillDeposits(fulfillAmount, "");

        // Before executeDeposit, check epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, 1000);
        assertEq(assetsFulfilled, 600);
        assertEq(sharesReceived, 599400); // 600 * 1_000_000 / 1001 = 599400.599... rounded down

        vault.executeDeposit(Alice, 0);
        vm.stopPrank();

        // Alice should get exactly 599400 shares (600 * 599400 / 600 = 599400)
        // Her basis should be exactly 600 (the amount fulfilled for her)
        assertEq(vault.balanceOf(Alice), 599400);
        assertEq(vault.userBasis(Alice), 600);

        // Remaining 400 should move to next epoch
        assertEq(vault.queuedDeposit(Alice, 1), 400);
        assertEq(vault.queuedDeposit(Alice, 0), 0);
    }

    function test_partial_withdrawal_exact_numbers() public {
        vm.prank(Alice);
        vault.requestDeposit(1000 ether);

        vm.startPrank(Manager);
        accountant.setNav(1000 ether);
        vault.fulfillDeposits(1000 ether, "");
        vault.executeDeposit(Alice, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // She withdraws exactly 30% of her shares
        uint256 sharesToWithdraw = (aliceShares * 30) / 100;
        vm.stopPrank();

        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Only fulfill 50% of what she requested
        uint256 sharesToFulfill = (sharesToWithdraw * 50) / 100;
        vm.startPrank(Manager);
        accountant.setNav(2000 ether);
        vault.fulfillWithdrawals(sharesToFulfill, 1000 ether, "");

        // Before executeWithdrawal, check epoch state
        (uint128 sharesWithdrawn, , uint128 sharesFulfilled) = vault.withdrawalEpochState(0);
        assertEq(sharesWithdrawn, sharesToWithdraw);
        assertEq(sharesFulfilled, sharesToFulfill);

        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        uint256 assetsReceived_actual = token.balanceOf(Alice) - aliceBalanceBefore;

        // Alice should receive exactly 298500000000000000000 wei (298.5 ether)
        assertEq(
            assetsReceived_actual,
            298500000000000000000,
            "Alice should receive exactly the correct proportional amount for her fulfilled shares"
        );

        // Remaining shares should move to next epoch
        uint256 expectedRemaining = sharesToWithdraw - sharesToFulfill;
        (uint128 remainingAmount, ) = vault.queuedWithdrawal(Alice, 1);
        assertEq(remainingAmount, expectedRemaining);
    }

    /// @notice Test multiple users partial deposit with exact numbers
    function test_multiple_users_partial_deposit_exact_numbers() public {
        // Alice deposits 600, Bob deposits 400, total 1000
        // Only fulfill 500 total
        // Alice should get 300 fulfilled, Bob should get 200 fulfilled

        vm.prank(Alice);
        vault.requestDeposit(600);
        vm.prank(Bob);
        vault.requestDeposit(400);

        vm.startPrank(Manager);
        accountant.setNav(1500);
        // totalAssets = 1500 + 1 - 1000 - 0 = 501
        // shares for 500 fulfilled: 500 * 1_000_000 / 501 = 998_003 shares
        vault.fulfillDeposits(500, "");

        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);
        vm.stopPrank();

        // Alice gets shares: userAssetsDeposited=300, sharesReceived=300*998003/500=598801 (rounded down)
        // Bob gets shares: userAssetsDeposited=200, sharesReceived=200*998003/500=399201 (rounded down)
        assertEq(vault.balanceOf(Alice), 598801);
        assertEq(vault.balanceOf(Bob), 399201);

        // Basis should be exactly the fulfilled amounts
        assertEq(vault.userBasis(Alice), 300);
        assertEq(vault.userBasis(Bob), 200);

        // Remaining amounts should move to next epoch
        assertEq(vault.queuedDeposit(Alice, 1), 300); // 600 - 300
        assertEq(vault.queuedDeposit(Bob, 1), 200); // 400 - 200
    }

    /// @notice Test partial deposit with specific values to verify correct share calculation
    function test_partial_deposit_share_calculation() public {
        // Scenario: Alice deposits 1000, only 600 is fulfilled
        // Expected: Alice should get shares proportional to her 600 fulfilled

        vm.prank(Alice);
        vault.requestDeposit(1000);

        vm.startPrank(Manager);
        accountant.setNav(2000);
        vault.fulfillDeposits(600, ""); // Only fulfill 600 out of 1000

        // Check epoch state
        (uint128 assetsDeposited, uint128 sharesReceived, uint128 assetsFulfilled) = vault
            .depositEpochState(0);
        assertEq(assetsDeposited, 1000);
        assertEq(assetsFulfilled, 600);
        assertEq(sharesReceived, 599400); // 600 * 1_000_000 / 1001

        vault.executeDeposit(Alice, 0);
        vm.stopPrank();

        // Alice should receive the correct proportional shares:
        // userAssetsDeposited = 1000 * 600 / 1000 = 600
        // sharesReceived = 600 * 599400 / 600 = 599400
        assertEq(vault.balanceOf(Alice), 599400);
        assertEq(vault.userBasis(Alice), 600);
        assertEq(vault.queuedDeposit(Alice, 1), 400); // Remaining unfulfilled
    }

    /// @notice Test the specific scenario: Alice withdraws 100 shares worth 1 ETH, 75 shares fulfilled
    function test_withdrawal_scenario_verification() public {
        // Setup: Alice deposits to get shares worth exactly 1 ETH
        vm.prank(Alice);
        vault.requestDeposit(1 ether);

        vm.startPrank(Manager);
        accountant.setNav(1 ether);
        vault.fulfillDeposits(1 ether, "");
        vault.executeDeposit(Alice, 0);

        uint256 aliceShares = vault.balanceOf(Alice);
        // Alice gets shares based on the actual calculation

        // Alice withdraws 100e18 shares (representing 100 wei worth)
        uint256 sharesToWithdraw = 100e18;
        vm.stopPrank();

        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Fulfill 75e18 out of 100e18 shares (75% fulfillment)
        uint256 sharesToFulfill = 75e18;
        vm.startPrank(Manager);
        accountant.setNav(1 ether); // Keep same NAV

        // Calculate expected assets for 75e18 shares
        uint256 expectedAssetsFor75Shares = (75e18 * 1 ether) / aliceShares;

        vault.fulfillWithdrawals(sharesToFulfill, expectedAssetsFor75Shares, "");

        // Check epoch state
        (uint128 sharesWithdrawn, uint128 assetsReceived, uint128 sharesFulfilled) = vault
            .withdrawalEpochState(0);
        assertEq(sharesWithdrawn, sharesToWithdraw);
        assertEq(sharesFulfilled, sharesToFulfill);
        assertEq(assetsReceived, expectedAssetsFor75Shares);

        // Execute Alice's withdrawal
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        uint256 assetsReceived_actual = token.balanceOf(Alice) - aliceBalanceBefore;

        // Alice should receive exactly the assets for her 75e18 fulfilled shares
        // sharesToFulfill for Alice = (100e18 * 75e18) / 100e18 = 75e18
        // assetsToWithdraw = Math.mulDiv(75e18, expectedAssetsFor75Shares, 75e18) = expectedAssetsFor75Shares
        assertEq(
            assetsReceived_actual,
            expectedAssetsFor75Shares,
            "Alice should receive assets for exactly 75e18 shares"
        );

        // Verify remaining 25e18 shares moved to next epoch
        (uint128 remainingAmount, ) = vault.queuedWithdrawal(Alice, 1);
        assertEq(
            remainingAmount,
            sharesToWithdraw - sharesToFulfill,
            "25e18 shares should remain unfulfilled"
        );
    }

    /// @notice Test exact scenario: 100 shares worth 1 ETH, 75% fulfillment should give 0.75 ETH
    function test_exact_withdrawal_calculation() public {
        // Setup: Create a scenario where 100 shares = exactly 1 ETH
        vm.prank(Alice);
        vault.requestDeposit(100 ether);

        vm.startPrank(Manager);
        accountant.setNav(100 ether);
        vault.fulfillDeposits(100 ether, "");
        vault.executeDeposit(Alice, 0);

        uint256 aliceShares = vault.balanceOf(Alice);

        // Alice withdraws 100 shares
        uint256 sharesToWithdraw = 100;
        vm.stopPrank();

        vm.prank(Alice);
        vault.requestWithdrawal(uint128(sharesToWithdraw));

        // Manager fulfills only 75 shares (75% fulfillment)
        uint256 sharesToFulfill = 75;
        vm.startPrank(Manager);
        accountant.setNav(100 ether); // Same NAV, so 100 shares should be worth 1 ETH

        // Calculate what 100 shares are worth: 100 * 100 ether / aliceShares
        uint256 valueOf100Shares = (100 * 100 ether) / aliceShares;

        // Calculate what 75 shares should be worth: 75% of that
        uint256 expectedAssetsFor75Shares = (75 * 100 ether) / aliceShares;

        vault.fulfillWithdrawals(sharesToFulfill, expectedAssetsFor75Shares, "");

        // Execute Alice's withdrawal
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        vault.executeWithdrawal(Alice, 0);
        vm.stopPrank();

        uint256 assetsReceived = token.balanceOf(Alice) - aliceBalanceBefore;

        // Verify Alice receives exactly the value of 75 shares
        assertEq(
            assetsReceived,
            expectedAssetsFor75Shares,
            "Alice should receive exactly 75% of her withdrawal value"
        );

        // Verify the proportionality: if 100 shares were worth valueOf100Shares,
        // then 75 shares should be worth 75% of that
        uint256 expectedProportion = (valueOf100Shares * 75) / 100;
        assertEq(
            assetsReceived,
            expectedProportion,
            "Assets should be exactly proportional to fulfilled shares"
        );

        // Verify remaining 25 shares moved to next epoch
        (uint128 remainingAmount, ) = vault.queuedWithdrawal(Alice, 1);
        assertEq(remainingAmount, 25, "Exactly 25 shares should remain unfulfilled");
    }
}
