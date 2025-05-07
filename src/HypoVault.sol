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

/// @author dyedm1
contract HypoVault is ERC20Minimal, Multicall, Ownable {
    using Address for address;
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct PendingDeposit {
        uint128 amount; // assets for deposits, shares for withdrawals
        uint128 sharesFulfilledLast; // the amount of shares fulfilled in the epoch when the deposit was last executed
    }

    struct PendingWithdrawal {
        uint128 amount; // shares for withdrawals
        uint128 basis; // the amount of assets used to mint the shares requested
    }

    struct EpochState {
        uint128 availableAssets; // assets that have been deposited or can be withdrawn
        uint128 availableShares; // shares that have been withdrawn or can be redeemed
        uint128 amountPending; // assets for deposits, shares for withdrawals
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Only the vault manager is authorized to call this function
    error NotManager();

    /// @notice The requested epoch in which to execute a deposit or withdrawal has not yet been fulfilled
    error EpochNotFulfilled();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlyingToken;

    uint256 public immutable performanceFeeBps;

    address public feeWallet;

    address public manager;

    IVaultAccountant public accountant;

    uint128 public withdrawalEpoch;

    uint128 public depositEpoch;

    uint256 public withdrawableAssets;

    mapping(uint256 epoch => EpochState) public depositEpochState;
    mapping(uint256 epoch => EpochState) public withdrawalEpochState;

    mapping(address user => mapping(uint256 epoch => PendingDeposit queue)) public queuedDeposit;
    mapping(address user => mapping(uint256 epoch => PendingWithdrawal queue))
        public queuedWithdrawal;
    mapping(address user => uint256 basis) public userBasis;

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

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    function setAccountant(address _accountant) external onlyOwner {
        accountant = IVaultAccountant(_accountant);
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT/REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    function requestDeposit(uint128 assets, address receiver) external {
        uint256 currentEpoch = depositEpoch;
        PendingDeposit memory pendingDeposit = queuedDeposit[receiver][currentEpoch];

        queuedDeposit[receiver][currentEpoch] = PendingDeposit({
            amount: pendingDeposit.amount + assets,
            sharesFulfilledLast: 0
        });

        depositEpochState[currentEpoch].availableAssets += assets;

        SafeTransferLib.safeTransferFrom(underlyingToken, msg.sender, address(this), assets);
    }

    // cancels a pending deposit in the current epoch
    function cancelDeposit(address cancellee, uint128 canceledAssets) external onlyManager {
        uint256 currentEpoch = depositEpoch;
        EpochState memory _depositEpochState = depositEpochState[currentEpoch];

        // reduced original deposit amount based on the amount of assets that have been fulfilled
        uint128 reduceBy = uint128(
            Math.mulDivRoundingUp(
                canceledAssets,
                _depositEpochState.availableAssets,
                _depositEpochState.amountPending
            )
        );

        queuedDeposit[cancellee][currentEpoch].amount -= reduceBy;

        _depositEpochState.availableAssets -= reduceBy;
    }

    // convert an active pending deposit into shares
    // can be called multiple times as more of the deposit becomes fulfilled
    function executeDeposit(address user, uint256 epoch) external {
        require(depositEpoch > epoch, "HypoVault: deposit not yet processed");

        PendingDeposit memory pendingDeposit = queuedDeposit[user][epoch];
        EpochState memory _depositEpochState = depositEpochState[epoch];

        // shares from pending deposits are already added to the supply at the start of every new epoch
        _mintVirtual(
            user,
            Math.mulDiv(
                pendingDeposit.amount,
                _depositEpochState.availableShares - pendingDeposit.sharesFulfilledLast,
                _depositEpochState.availableAssets
            )
        );

        userBasis[user] += Math.mulDivRoundingUp(
            pendingDeposit.amount,
            _depositEpochState.availableAssets - _depositEpochState.amountPending,
            _depositEpochState.availableAssets
        );

        queuedDeposit[user][epoch] = PendingDeposit({
            amount: pendingDeposit.amount,
            sharesFulfilledLast: _depositEpochState.availableShares
        });
    }

    // queues a withdrawal that executes at the beginning of the next epoch
    function requestWithdrawal(uint128 shares, address receiver) external {
        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[receiver][withdrawalEpoch];

        uint256 previousBasis = userBasis[msg.sender];
        uint256 withdrawalBasis = Math.mulDivRoundingUp(
            shares,
            previousBasis,
            balanceOf[msg.sender]
        );

        userBasis[msg.sender] = previousBasis - withdrawalBasis;

        queuedWithdrawal[receiver][withdrawalEpoch] = PendingWithdrawal({
            amount: pendingWithdrawal.amount + shares,
            basis: uint128(withdrawalBasis)
        });

        withdrawalEpochState[withdrawalEpoch].availableShares += shares;

        _burnVirtual(msg.sender, shares);
    }

    // convert an active pending withdrawal into assets
    function executeWithdrawal(address user, uint256 epoch) external {
        require(withdrawalEpoch > epoch, "HypoVault: withdrawal not yet processed");

        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[user][epoch];

        EpochState memory _withdrawalEpochState = withdrawalEpochState[epoch];

        uint256 assetsToWithdraw = Math.mulDiv(
            pendingWithdrawal.amount * _withdrawalEpochState.amountPending,
            _withdrawalEpochState.availableAssets,
            _withdrawalEpochState.availableShares ** 2
        );

        withdrawableAssets -= assetsToWithdraw;

        int256 performanceFee = ((int256(assetsToWithdraw) -
            int256(
                Math.mulDivRoundingUp(
                    pendingWithdrawal.basis,
                    _withdrawalEpochState.amountPending,
                    _withdrawalEpochState.availableAssets
                )
            )) * int256(performanceFeeBps)) / 10_000;

        queuedWithdrawal[user][epoch] = PendingWithdrawal({amount: 0, basis: 0});

        if (_withdrawalEpochState.amountPending > 0) {
            PendingWithdrawal memory nextQueuedWithdrawal = queuedWithdrawal[user][epoch + 1];
            queuedWithdrawal[user][epoch + 1] = PendingWithdrawal({
                amount: nextQueuedWithdrawal.amount +
                    (pendingWithdrawal.amount * _withdrawalEpochState.amountPending) /
                    _withdrawalEpochState.availableShares,
                basis: nextQueuedWithdrawal.basis +
                    (pendingWithdrawal.basis * _withdrawalEpochState.amountPending) /
                    _withdrawalEpochState.availableShares
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

    // assigns a share price for all deposits in the current epoch and increments the deposit epoch
    function fulfillDeposits(
        uint256 assetsToFulfill,
        bytes memory managerInput
    ) external onlyManager {
        uint256 currentEpoch = depositEpoch;

        EpochState memory epochState = depositEpochState[currentEpoch];

        EpochState memory previousEpochState;
        unchecked {
            // for epoch 0, point the previous epoch state to a blank slot (depositEpochState[UINT256_MAX])
            previousEpochState = depositEpochState[currentEpoch - 1];
        }

        uint256 totalAssets = accountant.computeNAV(address(this), managerInput) +
            1 -
            previousEpochState.amountPending -
            epochState.availableAssets -
            withdrawableAssets;

        // if the previous epoch has not been fulfilled completely, this operation must occur on the previous epoch
        if (previousEpochState.amountPending > 0) {
            currentEpoch--;
            epochState = previousEpochState;
        } else if (epochState.amountPending == 0) {
            // increment the epoch for new deposits if the previous epoch has been fulfilled completely
            depositEpoch = uint128(currentEpoch + 1);
            epochState.amountPending = epochState.availableAssets;
        }

        uint256 _totalSupply = totalSupply;

        uint256 sharesReceived = Math.mulDiv(assetsToFulfill, _totalSupply, totalAssets);

        uint256 amountPendingNew = epochState.amountPending - assetsToFulfill;

        if (amountPendingNew == 0) {
            depositEpoch = uint128(currentEpoch + 1);
        }

        depositEpochState[currentEpoch] = EpochState({
            availableAssets: uint128(epochState.availableAssets),
            availableShares: uint128(epochState.availableShares + sharesReceived),
            amountPending: uint128(amountPendingNew)
        });

        totalSupply = _totalSupply + Math.mulDiv(assetsToFulfill, _totalSupply, totalAssets);
    }

    // assigns a share price for all withdrawals in the current epoch and increments the withdrawal epoch
    function fulfillWithdrawals(
        uint256 sharesToFulfill,
        uint256 maxAssetsReceived,
        bytes memory managerInput
    ) external onlyManager {
        uint256 depositEpochCurrent = depositEpoch;

        uint256 _withdrawableAssets = withdrawableAssets;
        uint256 totalAssets = accountant.computeNAV(address(this), managerInput) +
            1 -
            depositEpochState[depositEpochCurrent - 1].amountPending -
            depositEpochState[depositEpochCurrent].availableAssets -
            _withdrawableAssets;

        uint256 currentEpoch = withdrawalEpoch;

        EpochState memory epochState = withdrawalEpochState[currentEpoch];

        uint256 _totalSupply = totalSupply;

        uint256 assetsReceived = Math.mulDiv(sharesToFulfill, totalAssets, _totalSupply);

        require(
            assetsReceived <= maxAssetsReceived,
            "HypoVault: assets received exceeds max assets received"
        );

        uint256 sharesRemaining = epochState.amountPending - sharesToFulfill;

        withdrawalEpochState[currentEpoch] = EpochState({
            availableAssets: uint128(assetsReceived),
            availableShares: uint128(epochState.availableShares),
            amountPending: uint128(sharesRemaining)
        });

        currentEpoch++;

        withdrawalEpoch = uint128(currentEpoch);

        withdrawalEpochState[currentEpoch] = EpochState({
            availableAssets: 0,
            availableShares: uint128(sharesRemaining),
            amountPending: 0
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
