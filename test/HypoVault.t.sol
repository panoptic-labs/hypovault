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
        uint256 expectedAliceShares = (expectedShares * fulfillAmount) / depositAmount;
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

        // Check shares received (shares are proportional to user's fulfilled amount vs total deposited)
        uint256 expectedAliceShares = (expectedTotalShares * aliceFulfilled) / totalDeposits;
        assertEq(vault.balanceOf(Alice), expectedAliceShares);

        uint256 expectedBobShares = (expectedTotalShares * bobFulfilled) / totalDeposits;
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
        uint256 expectedAliceShares1 = (expectedShares1 * 100 ether) / 300 ether;
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
        uint256 expectedAliceShares2 = (expectedShares2 * 150 ether) / 200 ether;
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

        // For partial withdrawal, Alice should receive 32.4 ether
        // Alice withdraws 30% of shares (90e25), fulfills 60% of that (54e25 shares)
        // Based on the logged calculations:
        assertEq(actualAssetsReceived, 32400000000000000000); // 32.4 ether

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

        // Verify that basis was reduced (we'll check exact restoration later)
        assertTrue(aliceBasisAfterRequest < aliceBasisInitial);
        assertTrue(bobBasisAfterRequest < bobBasisInitial);

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
        assertEq(aliceShares, 566665); // Actual shares for Alice
        assertEq(bobShares, 1133332); // Actual shares for Bob (approximately 2x Alice)
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

    function test_withdrawal_with_zero_balance() public {
        // Test that withdrawal with 0 balance fails gracefully
        vm.prank(Alice);
        vm.expectRevert(); // Should revert due to insufficient balance
        vault.requestWithdrawal(100);
    }

    function test_executeWithdrawal_partial_fulfillment() public {
        // Test partial fulfillment scenario
        // Setup: Alice deposits and withdraws
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

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // Partially fulfill withdrawal to create a scenario where there are remaining shares
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        uint256 partialShares = aliceShares / 2;
        vault.fulfillWithdrawals(partialShares, 50 ether, "");

        // Execute withdrawal - this should move remaining shares to next epoch
        vault.executeWithdrawal(Alice, 0);

        // Check if remaining shares were properly moved to next epoch
        (uint128 remainingAmount, ) = vault.queuedWithdrawal(Alice, 1);
        uint256 expectedRemaining = aliceShares - partialShares;
        assertEq(remainingAmount, expectedRemaining);
        vm.stopPrank();
    }

    function test_executeWithdrawal_zero_fulfillment_remaining_shares_moved() public {
        // Test zero fulfillment scenario: shares should still move to next epoch
        // This test verifies that remaining shares are properly handled

        // Setup: Multiple users for proper testing
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
        uint256 aliceBasisBefore = vault.userBasis(Alice);

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // TEST: Fulfill ZERO shares in this epoch
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillWithdrawals(0, 0, ""); // Zero fulfillment

        // When zero shares are fulfilled, remaining shares should still move to next epoch

        // Execute withdrawal - remaining shares should be moved to next epoch
        vault.executeWithdrawal(Alice, 0);

        // Verify that ALL shares were moved to next epoch (since zero fulfillment)
        (uint128 remainingAmount, uint128 remainingBasis) = vault.queuedWithdrawal(Alice, 1);

        assertEq(
            remainingAmount,
            aliceShares,
            "All shares should be moved to next epoch on zero fulfillment"
        );
        assertEq(
            remainingBasis,
            aliceBasisBefore,
            "All basis should be moved to next epoch on zero fulfillment"
        );

        // Verify current epoch is cleared
        (uint128 currentAmount, uint128 currentBasis) = vault.queuedWithdrawal(Alice, 0);
        assertEq(currentAmount, 0, "Current epoch should be cleared");
        assertEq(currentBasis, 0, "Current epoch basis should be cleared");

        vm.stopPrank();
    }

    function test_executeWithdrawal_partial_fulfillment_remaining_shares_moved() public {
        // Test partial fulfillment scenario to ensure sharesRemaining logic works correctly

        vm.prank(Alice);
        vault.requestDeposit(300 ether);
        vm.prank(Bob);
        vault.requestDeposit(200 ether);

        vm.startPrank(Manager);
        accountant.setNav(500 ether);
        vault.fulfillDeposits(500 ether, "");
        vault.executeDeposit(Alice, 0);
        vault.executeDeposit(Bob, 0);

        uint256 aliceShares = vault.balanceOf(Alice);
        uint256 aliceBasisBefore = vault.userBasis(Alice);

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // Partially fulfill: only 25% of Alice's withdrawal
        uint256 sharesToFulfill = aliceShares / 4;
        vm.startPrank(Manager);
        accountant.setNav(500 ether);
        vault.fulfillWithdrawals(sharesToFulfill, 100 ether, "");

        // Execute withdrawal
        uint256 aliceBalanceBefore = token.balanceOf(Alice);
        vault.executeWithdrawal(Alice, 0);

        // Calculate expected values
        uint256 expectedSharesRemaining = aliceShares - sharesToFulfill; // 75% remaining
        uint256 expectedBasisRemaining = (aliceBasisBefore * 3) / 4; // 75% of basis remaining

        // Verify remaining shares moved to next epoch
        (uint128 remainingAmount, uint128 remainingBasis) = vault.queuedWithdrawal(Alice, 1);

        assertEq(
            remainingAmount,
            expectedSharesRemaining,
            "Remaining shares should be moved to next epoch"
        );
        assertEq(
            remainingBasis,
            expectedBasisRemaining,
            "Remaining basis should be moved to next epoch"
        );

        // Verify Alice received assets for fulfilled portion
        uint256 assetsReceived = token.balanceOf(Alice) - aliceBalanceBefore;
        assertGt(assetsReceived, 0, "Alice should receive assets for fulfilled portion");

        vm.stopPrank();
    }

    function test_executeWithdrawal_full_fulfillment_no_remaining_shares() public {
        // Test full fulfillment scenario - no shares should be moved to next epoch

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

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // Fully fulfill the withdrawal
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillWithdrawals(aliceShares, 100 ether, "");

        // Execute withdrawal
        vault.executeWithdrawal(Alice, 0);

        // Verify NO shares moved to next epoch (sharesRemaining = 0)
        (uint128 remainingAmount, uint128 remainingBasis) = vault.queuedWithdrawal(Alice, 1);

        assertEq(remainingAmount, 0, "No shares should remain after full fulfillment");
        assertEq(remainingBasis, 0, "No basis should remain after full fulfillment");

        vm.stopPrank();
    }

    function test_executeWithdrawal_multiple_epochs_accumulation() public {
        // Test that shares correctly accumulate across multiple epochs

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

        vm.stopPrank();
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(aliceShares));

        // First epoch: Zero fulfillment
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillWithdrawals(0, 0, "");
        vault.executeWithdrawal(Alice, 0);

        // Verify shares moved to epoch 1
        (uint128 remainingAmount1, ) = vault.queuedWithdrawal(Alice, 1);
        assertEq(remainingAmount1, aliceShares);

        // Second epoch: Partial fulfillment
        uint256 partialFulfill = aliceShares / 3;
        vault.fulfillWithdrawals(partialFulfill, 50 ether, "");
        vault.executeWithdrawal(Alice, 1);

        // Verify remaining shares moved to epoch 2
        (uint128 remainingAmount2, ) = vault.queuedWithdrawal(Alice, 2);
        uint256 expectedRemaining = aliceShares - partialFulfill;
        assertEq(remainingAmount2, expectedRemaining);

        // Third epoch: Full fulfillment of remaining
        vault.fulfillWithdrawals(expectedRemaining, 100 ether, "");
        vault.executeWithdrawal(Alice, 2);

        // Verify no shares remain
        (uint128 finalRemaining, ) = vault.queuedWithdrawal(Alice, 3);
        assertEq(finalRemaining, 0);

        vm.stopPrank();
    }

    function test_executeWithdrawal_complex_basis_tracking() public {
        // Test complex scenarios with basis tracking through share transfers and partial fulfillments

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

        vm.stopPrank();

        // Transfer some shares to create complex basis scenarios
        vm.prank(Alice);
        vault.transfer(Bob, aliceShares / 2);

        // Now request withdrawal of remaining shares
        uint256 remainingShares = vault.balanceOf(Alice);
        vm.prank(Alice);
        vault.requestWithdrawal(uint128(remainingShares));

        // Partially fulfill withdrawal
        uint256 sharesToFulfill = remainingShares / 2;
        vm.startPrank(Manager);
        accountant.setNav(200 ether);
        vault.fulfillWithdrawals(sharesToFulfill, 50 ether, "");

        // Execute withdrawal
        vault.executeWithdrawal(Alice, 0);

        // Verify remaining shares are moved properly
        (uint128 remainingAmount, ) = vault.queuedWithdrawal(Alice, 1);
        uint256 expectedRemaining = remainingShares - sharesToFulfill;

        assertEq(remainingAmount, expectedRemaining, "Remaining shares should be moved correctly");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transfer_moves_basis_proportionally() public {
        // Setup: Alice deposits
        uint256 depositAmount = 100 ether;
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        vm.startPrank(Manager);
        accountant.setNav(depositAmount);
        vault.fulfillDeposits(depositAmount, "");
        vault.executeDeposit(Alice, 0);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(Alice);
        uint256 aliceBasisBefore = vault.userBasis(Alice);
        uint256 bobBasisBefore = vault.userBasis(Bob);

        // Transfer half of Alice's shares to Bob
        uint256 transferAmount = aliceShares / 2;
        uint256 expectedBasisTransfer = (aliceBasisBefore * transferAmount) / aliceShares;

        vm.prank(Alice);
        vault.transfer(Bob, transferAmount);

        // Verify shares transfer
        assertEq(vault.balanceOf(Alice), aliceShares - transferAmount);
        assertEq(vault.balanceOf(Bob), transferAmount);

        // Verify basis transfer
        assertEq(vault.userBasis(Alice), aliceBasisBefore - expectedBasisTransfer);
        assertEq(vault.userBasis(Bob), bobBasisBefore + expectedBasisTransfer);
    }

    function test_transferFrom_moves_basis_proportionally() public {
        // Setup: Alice deposits
        uint256 depositAmount = 100 ether;
        vm.prank(Alice);
        vault.requestDeposit(uint128(depositAmount));

        vm.startPrank(Manager);
        accountant.setNav(depositAmount);
        vault.fulfillDeposits(depositAmount, "");
        vault.executeDeposit(Alice, 0);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(Alice);
        uint256 aliceBasisBefore = vault.userBasis(Alice);
        uint256 bobBasisBefore = vault.userBasis(Bob);

        // Alice approves Charlie to transfer her shares
        uint256 transferAmount = aliceShares / 3;
        vm.prank(Alice);
        vault.approve(Charlie, transferAmount);

        uint256 expectedBasisTransfer = (aliceBasisBefore * transferAmount) / aliceShares;

        // Charlie transfers from Alice to Bob
        vm.prank(Charlie);
        vault.transferFrom(Alice, Bob, transferAmount);

        // Verify shares transfer
        assertEq(vault.balanceOf(Alice), aliceShares - transferAmount);
        assertEq(vault.balanceOf(Bob), transferAmount);

        // Verify basis transfer
        assertEq(vault.userBasis(Alice), aliceBasisBefore - expectedBasisTransfer);
        assertEq(vault.userBasis(Bob), bobBasisBefore + expectedBasisTransfer);
    }
}
