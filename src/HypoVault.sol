// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Interfaces
import {ERC20Minimal} from "lib/panoptic-v1.1/contracts/tokens/ERC20Minimal.sol";
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultAccountant} from "./interfaces/IVaultAccountant.sol";
// Base
import {Multicall} from "lib/panoptic-v1.1/contracts/base/Multicall.sol";
import {Ownable} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
// Libraries
import {Address} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {Math} from "lib/panoptic-v1.1/contracts/libraries/Math.sol";
import {SafeTransferLib} from "lib/panoptic-v1.1/contracts/libraries/SafeTransferLib.sol";

/// @author Axicon Labs Limited
/// @notice A vault that allows a manager to allocate assets deposited by users and distribute profits asynchronously.
contract HypoVault is ERC20Minimal, Multicall, Ownable {
    using Math for uint256;
    using Address for address;
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice A type that represents an unfulfilled or partially fulfilled withdrawal.
    /// @param amount The amount of shares requested
    /// @param basis The amount of assets used to mint the shares requested
    struct PendingWithdrawal {
        uint128 amount;
        uint128 basis;
    }

    /// @notice A type that represents the state of an epoch.
    /// @param availableAssets The amount of assets that have been deposited or can be withdrawn
    /// @param availableShares The amount of shares that have been withdrawn or can be redeemed
    /// @param amountFulfilled The amount of assets fulfilled for deposits, shares fulfilled for withdrawals
    struct EpochState {
        uint128 availableAssets;
        uint128 availableShares;
        uint128 amountFulfilled;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Only the vault manager is authorized to call this function
    error NotManager();

    /// @notice The requested epoch in which to execute a deposit or withdrawal has not yet been fulfilled
    error EpochNotFulfilled();

    /// @notice The withdrawal fulfillment exceeds the maximum amount of assets that can be received
    error WithdrawalNotFulfillable();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Token used to denominate deposits and withdrawals.
    address public immutable underlyingToken;

    /// @notice Performance fee, in basis points, taken on each profitable withdrawal.
    uint256 public immutable performanceFeeBps;

    /// @notice Wallet that receives the performance fee.
    address public feeWallet;

    /// @notice Account authorized to execute deposits, withdrawals, and make arbitrary function calls from the vault.
    address public manager;

    /// @notice Contract that reports the net asset value of the vault.
    IVaultAccountant public accountant;

    /// @notice Epoch number for which withdrawals are currently being executed.
    uint128 public withdrawalEpoch;

    /// @notice Epoch number for which deposits are currently being executed.
    uint128 public depositEpoch;

    /// @notice Assets in the vault reserved for fulfilled withdrawal requests.
    uint256 public withdrawableAssets;

    /// @notice Contains information about the quantity of assets requested and fulfilled for deposits in each epoch.
    mapping(uint256 epoch => EpochState) public depositEpochState;

    /// @notice Contains information about the quantity of shares requested and fulfilled for withdrawals in each epoch.
    mapping(uint256 epoch => EpochState) public withdrawalEpochState;

    /// @notice Records the state of a deposit request for a user in a given epoch.
    mapping(address user => mapping(uint256 epoch => uint128 depositAmount)) public queuedDeposit;

    /// @notice Records the state of a withdrawal request for a user in a given epoch.
    mapping(address user => mapping(uint256 epoch => PendingWithdrawal queue))
        public queuedWithdrawal;

    /// @notice Records the cost basis of a user's shares for the purpose of calculating performance fees.
    mapping(address user => uint256 basis) public userBasis;

    /// @notice Initializes the vault.
    /// @param _underlyingToken The token used to denominate deposits and withdrawals.
    /// @param _manager The account authorized to execute deposits, withdrawals, and make arbitrary function calls from the vault.
    /// @param _accountant The contract that reports the net asset value of the vault.
    /// @param _performanceFeeBps The performance fee, in basis points, taken on each profitable withdrawal.
    constructor(
        address _underlyingToken,
        address _manager,
        IVaultAccountant _accountant,
        uint256 _performanceFeeBps
    ) {
        underlyingToken = _underlyingToken;
        manager = _manager;
        accountant = _accountant;
        performanceFeeBps = _performanceFeeBps;
        totalSupply = 1_000_000;
    }

    /*//////////////////////////////////////////////////////////////
                                  AUTH
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier that restricts access to only the manager.
    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /// @notice Allows the owner to set the manager.
    /// @param _manager The new manager.
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    /// @notice Allows the owner to set the accountant.
    /// @param _accountant The new accountant.
    function setAccountant(address _accountant) external onlyOwner {
        accountant = IVaultAccountant(_accountant);
    }

    /// @notice Allows the owner to set the wallet that receives the performance fee.
    /// @param _feeWallet The new fee wallet.
    function setFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT/REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows a user to request a deposit of assets.
    /// @param assets The amount of assets to deposit
    /// @param receiver The address to receive the shares
    function requestDeposit(uint128 assets, address receiver) external {
        uint256 currentEpoch = depositEpoch;

        queuedDeposit[receiver][currentEpoch] += assets;

        depositEpochState[currentEpoch].availableAssets += assets;

        SafeTransferLib.safeTransferFrom(underlyingToken, msg.sender, address(this), assets);
    }

    // queues a withdrawal that executes at the beginning of the next epoch
    function requestWithdrawal(uint128 shares, address receiver) external {
        _burnVirtual(msg.sender, shares);

        uint256 _withdrawalEpoch = withdrawalEpoch;

        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[receiver][_withdrawalEpoch];

        uint256 previousBasis = userBasis[msg.sender];

        uint256 userBalance = balanceOf[msg.sender];

        uint256 withdrawalBasis = (previousBasis * shares) / balanceOf[msg.sender];

        userBasis[msg.sender] = previousBasis - withdrawalBasis;

        queuedWithdrawal[receiver][_withdrawalEpoch] = PendingWithdrawal({
            amount: pendingWithdrawal.amount + shares,
            basis: uint128(withdrawalBasis + ((shares * previousBasis) % userBalance) > 0 ? 1 : 0)
        });

        withdrawalEpochState[withdrawalEpoch].availableShares += shares;
    }

    /// @notice Allows the manager to cancel a deposit in the current (unfulfilled) epoch.
    /// @dev If deposited funds in previous epochs have not been completely fulfilled, the manager can execute those deposits to move the unfulfilled amount to the current epoch.
    /// @param user The address that requested the deposit
    function cancelDeposit(address user) external onlyManager {
        uint256 currentEpoch = depositEpoch;

        uint256 queuedDepositAmount = queuedDeposit[user][currentEpoch];
        queuedDeposit[user][currentEpoch] = 0;

        depositEpochState[currentEpoch].availableAssets -= uint128(queuedDepositAmount);

        SafeTransferLib.safeTransfer(underlyingToken, user, queuedDepositAmount);
    }

    /// @notice Allows the manager to cancel a withdrawal in the current (unfulfilled) epoch.
    /// @dev If withdrawn shares in previous epochs have not been completely fulfilled, the manager can execute those withdrawals to move the unfulfilled amount to the current epoch.
    /// @param user The address that requested the withdrawal
    function cancelWithdrawal(address user) external onlyManager {
        uint256 currentEpoch = withdrawalEpoch;

        uint128 queuedWithdrawalAmount = queuedWithdrawal[user][currentEpoch].amount;
        queuedWithdrawal[user][currentEpoch].amount = 0;

        withdrawalEpochState[currentEpoch].availableShares -= queuedWithdrawalAmount;

        _mintVirtual(user, queuedWithdrawalAmount);
    }

    /// @notice Allows the manager to convert an active pending deposit into shares.
    /// @param user The address that requested the deposit
    /// @param epoch The epoch in which the deposit was requested
    function executeDeposit(address user, uint256 epoch) external {
        if (depositEpoch >= epoch) revert EpochNotFulfilled();

        uint256 queuedDepositAmount = queuedDeposit[user][epoch];
        queuedDeposit[user][epoch] = 0;

        EpochState memory _depositEpochState = depositEpochState[epoch];

        uint256 assetsDeposited = Math.mulDiv(
            queuedDepositAmount,
            _depositEpochState.amountFulfilled,
            _depositEpochState.availableAssets
        );

        // shares from pending deposits are already added to the supply at the start of every new epoch
        _mintVirtual(
            user,
            Math.mulDiv(
                assetsDeposited,
                _depositEpochState.availableShares,
                _depositEpochState.availableAssets
            )
        );

        userBasis[user] += assetsDeposited;

        queuedDeposit[user][epoch] = 0;

        uint256 assetsRemaining = queuedDepositAmount - assetsDeposited;
        if (assetsRemaining > 0) queuedDeposit[user][epoch + 1] += uint128(assetsRemaining);
    }

    // convert an active pending withdrawal into assets
    function executeWithdrawal(address user, uint256 epoch) external {
        if (withdrawalEpoch >= epoch) revert EpochNotFulfilled();

        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[user][epoch];

        EpochState memory _withdrawalEpochState = withdrawalEpochState[epoch];

        // prorated shares to fulfill = amount * fulfilled shares / total shares withdrawn
        uint256 sharesToFulfill = (uint256(pendingWithdrawal.amount) *
            _withdrawalEpochState.amountFulfilled) / _withdrawalEpochState.availableShares;
        // assets to withdraw = prorated shares to withdraw * assets fulfilled / total shares withdrawn
        uint256 assetsToWithdraw = Math.mulDiv(
            sharesToFulfill,
            _withdrawalEpochState.availableAssets,
            _withdrawalEpochState.availableShares
        );

        withdrawableAssets -= assetsToWithdraw;

        uint256 withdrawnBasis = (pendingWithdrawal.basis * _withdrawalEpochState.amountFulfilled) /
            _withdrawalEpochState.availableShares;
        uint256 performanceFee = (uint256(
            Math.max(0, int256(assetsToWithdraw) - int256(withdrawnBasis))
        ) * performanceFeeBps) / 10_000;

        queuedWithdrawal[user][epoch] = PendingWithdrawal({amount: 0, basis: 0});

        uint256 sharesRemaining = pendingWithdrawal.amount - sharesToFulfill;
        uint256 basisRemaining = pendingWithdrawal.basis - withdrawnBasis;
        if (sharesToFulfill + basisRemaining > 0) {
            PendingWithdrawal memory nextQueuedWithdrawal = queuedWithdrawal[user][epoch + 1];
            queuedWithdrawal[user][epoch + 1] = PendingWithdrawal({
                amount: uint128(nextQueuedWithdrawal.amount + sharesRemaining),
                basis: uint128(nextQueuedWithdrawal.basis + basisRemaining)
            });
        }

        if (performanceFee > 0) {
            assetsToWithdraw -= uint256(performanceFee);
            SafeTransferLib.safeTransfer(underlyingToken, feeWallet, uint256(performanceFee));
        }

        SafeTransferLib.safeTransfer(underlyingToken, user, assetsToWithdraw);
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows `manager` to make an arbitrary function call from this contract.
    function manage(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyManager returns (bytes memory result) {
        result = target.functionCallWithValue(data, value);
    }

    /// @notice Allows `manager` to make arbitrary function calls from this contract.
    function manage(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external onlyManager returns (bytes[] memory results) {
        uint256 targetsLength = targets.length;
        results = new bytes[](targetsLength);
        for (uint256 i; i < targetsLength; ++i) {
            results[i] = targets[i].functionCallWithValue(data[i], values[i]);
        }
    }

    /// @notice Allows the manager to fulfill deposit requests.
    /// @param assetsToFulfill The amount of assets to fulfill
    /// @param managerInput If provided, an arbitrary input to the accountant contract
    function fulfillDeposits(
        uint256 assetsToFulfill,
        bytes memory managerInput
    ) external onlyManager {
        uint256 currentEpoch = depositEpoch;

        EpochState memory epochState = depositEpochState[currentEpoch];

        uint256 totalAssets = accountant.computeNAV(address(this), managerInput) +
            1 -
            epochState.availableAssets -
            withdrawableAssets;

        uint256 _totalSupply = totalSupply;

        uint256 sharesReceived = Math.mulDiv(assetsToFulfill, _totalSupply, totalAssets);

        uint256 assetsRemaining = epochState.availableAssets - assetsToFulfill;

        depositEpochState[currentEpoch] = EpochState({
            availableAssets: uint128(epochState.availableAssets),
            availableShares: uint128(sharesReceived),
            amountFulfilled: uint128(assetsToFulfill)
        });

        currentEpoch++;
        depositEpoch = uint128(currentEpoch);

        depositEpochState[currentEpoch] = EpochState({
            availableAssets: 0,
            availableShares: uint128(assetsRemaining),
            amountFulfilled: 0
        });

        totalSupply = _totalSupply + sharesReceived;
    }

    /// @notice Allows the manager to fulfill withdrawal requests.
    /// @param sharesToFulfill The amount of shares to fulfill
    /// @param maxAssetsReceived The maximum amount of assets that can be received
    /// @param managerInput If provided, an arbitrary input to the accountant contract
    function fulfillWithdrawals(
        uint256 sharesToFulfill,
        uint256 maxAssetsReceived,
        bytes memory managerInput
    ) external onlyManager {
        uint256 _withdrawableAssets = withdrawableAssets;
        uint256 totalAssets = accountant.computeNAV(address(this), managerInput) +
            1 -
            depositEpochState[depositEpoch].availableAssets -
            _withdrawableAssets;

        uint256 currentEpoch = withdrawalEpoch;

        EpochState memory epochState = withdrawalEpochState[currentEpoch];

        uint256 _totalSupply = totalSupply;

        uint256 assetsReceived = Math.mulDiv(sharesToFulfill, totalAssets, _totalSupply);

        if (assetsReceived > maxAssetsReceived) revert WithdrawalNotFulfillable();

        uint256 sharesRemaining = epochState.amountFulfilled - sharesToFulfill;

        withdrawalEpochState[currentEpoch] = EpochState({
            availableAssets: uint128(assetsReceived),
            availableShares: uint128(epochState.availableShares),
            amountFulfilled: uint128(sharesToFulfill)
        });

        currentEpoch++;

        withdrawalEpoch = uint128(currentEpoch);

        withdrawalEpochState[currentEpoch] = EpochState({
            availableAssets: 0,
            availableShares: uint128(sharesRemaining),
            amountFulfilled: 0
        });

        totalSupply = _totalSupply - sharesToFulfill;

        withdrawableAssets = _withdrawableAssets + assetsReceived;
    }

    /// @notice Internal utility to mint tokens to a user's account without updating the total supply.
    /// @param to The user to mint tokens to
    /// @param amount The amount of tokens to mint
    function _mintVirtual(address to, uint256 amount) internal {
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    /// @notice Internal utility to burn tokens from a user's account without updating the total supply.
    /// @param from The user to burn tokens from
    /// @param amount The amount of tokens to burn
    function _burnVirtual(address from, uint256 amount) internal {
        balanceOf[from] -= amount;

        emit Transfer(from, address(0), amount);
    }
}
