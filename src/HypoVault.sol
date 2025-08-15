// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Interfaces
import {ERC20Minimal} from "lib/panoptic-v1.1/contracts/tokens/ERC20Minimal.sol";
import {IERC20} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVaultAccountant} from "./interfaces/IVaultAccountant.sol";
// Base
import {ERC721Holder} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Multicall} from "lib/panoptic-v1.1/contracts/base/Multicall.sol";
import {Ownable} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
// Libraries
import {Address} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {Math} from "lib/panoptic-v1.1/contracts/libraries/Math.sol";
import {SafeTransferLib} from "lib/panoptic-v1.1/contracts/libraries/SafeTransferLib.sol";

/// @author Axicon Labs Limited
/// @notice A vault in which a manager allocates assets deposited by users and distributes profits asynchronously.
contract HypoVault is ERC20Minimal, Multicall, Ownable, ERC721Holder, ERC1155Holder {
    using Math for uint256;
    using Address for address;
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice A type that represents an unfulfilled or partially fulfilled withdrawal.
    /// @param amount The amount of shares requested
    /// @param basis The amount of assets used to mint the shares requested
    /// @param ratioX64 The fraction of the requested shares that will be distributed in proceeds tokens
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    struct PendingWithdrawal {
        uint128 amount;
        uint128 basis;
        uint128 ratioX64;
        bool shouldRedeposit;
    }

    /// @notice A type that represents the state of a deposit epoch.
    /// @param assetsDeposited The amount of assets deposited
    /// @param sharesReceived The amount of shares received over `assetsFulfilled`
    /// @param assetsFulfilled The amount of assets fulfilled (out of `assetsDeposited`)
    struct DepositEpochState {
        uint128 assetsDeposited;
        uint128 sharesReceived;
        uint128 assetsFulfilled;
    }

    /// @notice A type that represents the state of a withdrawal epoch.
    /// @param sharesWithdrawn The amount of shares withdrawn
    /// @param depositAssetsReceived The amount of depositAssets received over `sharesFulfilled`
    /// @param proceedsAssetsReceived The amount of proceedsAssets received over `sharesFulfilled`
    /// @param sharesFulfilled The amount of shares fulfilled (out of `sharesWithdrawn`)
    struct WithdrawalEpochState {
        uint128 sharesWithdrawn;
        uint128 depositAssetsReceived;
        uint128 proceedsAssetsReceived;
        uint128 sharesFulfilled;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the manager address is updated
    /// @param oldManager The address of the previous manager
    /// @param newManager The address of the new manager
    event ManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when the accountant address is updated
    /// @param oldAccountant The address of the previous accountant
    /// @param newAccountant The address of the new accountant
    event AccountantUpdated(
        IVaultAccountant indexed oldAccountant,
        IVaultAccountant indexed newAccountant
    );

    /// @notice Emitted when the fee wallet address is updated
    /// @param oldFeeWallet The address of the previous fee wallet
    /// @param newFeeWallet The address of the new fee wallet
    event FeeWalletUpdated(address indexed oldFeeWallet, address indexed newFeeWallet);

    /// @notice Emitted when a deposit is requested.
    /// @param user The address that requested the deposit
    /// @param assets The amount of assets requested
    event DepositRequested(address indexed user, uint256 assets);

    /// @notice Emitted when a withdrawal is requested.
    /// @param user The address that requested the withdrawal
    /// @param shares The amount of shares requested
    /// @param ratioX64 The fraction of the requested shares that will be distributed in proceeds tokens
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    event WithdrawalRequested(
        address indexed user,
        uint256 shares,
        uint128 ratioX64,
        bool shouldRedeposit
    );

    /// @notice Emitted when a deposit is cancelled.
    /// @param user The address that requested the deposit
    /// @param assets The amount of assets requested
    event DepositCancelled(address indexed user, uint256 assets);

    /// @notice Emitted when a withdrawal is cancelled.
    /// @param user The address that requested the withdrawal
    /// @param shares The amount of shares requested
    event WithdrawalCancelled(address indexed user, uint256 shares);

    /// @notice Emitted when a deposit is executed.
    /// @param user The address that requested the deposit
    /// @param assets The amount of assets executed
    /// @param shares The amount of shares received
    /// @param epoch The epoch in which the deposit was executed
    event DepositExecuted(address indexed user, uint256 assets, uint256 shares, uint256 epoch);

    /// @notice Emitted when a withdrawal is executed.
    /// @param user The address that requested the withdrawal
    /// @param shares The amount of shares executed
    /// @param assets The amount of assets received
    /// @param performanceFee The amount of performance fee received from the deposit token
    /// @param performanceFeeProceeds The amount of performance fee received from the proceeds token
    /// @param epoch The epoch in which the withdrawal was executed
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    event WithdrawalExecuted(
        address indexed user,
        uint256 shares,
        uint256 assets,
        uint256 performanceFee,
        uint256 performanceFeeProceeds,
        uint256 epoch,
        bool shouldRedeposit
    );

    /// @notice Emitted when the redeposit status of a withdrawal request is changed.
    /// @param user The address that changed the redeposit status
    /// @param epoch The epoch of the withdrawal request
    /// @param shouldRedeposit The new redeposit status
    event RedepositStatusChanged(address indexed user, uint256 indexed epoch, bool shouldRedeposit);

    /// @notice Emitted when deposits are fulfilled.
    /// @param epoch The epoch in which the deposits were fulfilled
    /// @param assetsFulfilled The amount of assets fulfilled
    /// @param sharesReceived The amount of shares received
    event DepositsFulfilled(uint256 indexed epoch, uint256 assetsFulfilled, uint256 sharesReceived);

    /// @notice Emitted when withdrawals are fulfilled.
    /// @param epoch The epoch in which the next withdrawals were fulfilled
    /// @param depositAssetsReceived The amount of assets received
    /// @param sharesFulfilled The amount of shares fulfilled
    event WithdrawalsFulfilled(
        uint256 indexed epoch,
        uint256 depositAssetsReceived,
        uint256 sharesFulfilled
    );

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
    address public immutable depositToken;

    /// @notice Alternative token used to denominate withdrawals.
    address public immutable proceedsToken;

    /// @notice Performance fee, in basis points, taken on each profitable withdrawal.
    uint256 public immutable performanceFeeBps;

    /// @notice Performance fee for proceeds token, in basis points, taken on each profitable withdrawal.
    uint256 public immutable performanceFeeProceedsBps;

    /// @notice Symbol of the share token.
    string public symbol;

    /// @notice Name of the share token.
    string public name;

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

    /// @notice Deposit assets in the vault reserved for fulfilled withdrawal requests.
    uint256 public reservedWithdrawalDepositAssets;

    /// @notice Proceeds assets in the vault reserved for fulfilled withdrawal requests.
    uint256 public reservedWithdrawalProceedsAssets;

    /// @notice Contains information about the quantity of assets requested and fulfilled for deposits in each epoch.
    mapping(uint256 epoch => DepositEpochState) public depositEpochState;

    /// @notice Contains information about the quantity of shares requested and fulfilled for withdrawals in each epoch.
    mapping(uint256 epoch => WithdrawalEpochState) public withdrawalEpochState;

    /// @notice Records the state of a deposit request for a user in a given epoch.
    mapping(address user => mapping(uint256 epoch => uint128 depositAmount)) public queuedDeposit;

    /// @notice Records the state of a withdrawal request for a user in a given epoch.
    mapping(address user => mapping(uint256 epoch => PendingWithdrawal queue))
        public queuedWithdrawal;

    /// @notice Records the cost basis of a user's shares for the purpose of calculating performance fees.
    mapping(address user => uint256 basis) public userBasis;

    /// @notice Initializes the vault.
    /// @param _depositToken The token used to denominate deposits and withdrawals.
    /// @param _proceedsToken The alternative token used to denominate withdrawals.
    /// @param _manager The account authorized to execute deposits, withdrawals, and make arbitrary function calls from the vault.
    /// @param _accountant The contract that reports the net asset value of the vault.
    /// @param _performanceFeeBps The performance fee, in basis points, taken on each profitable withdrawal.
    /// @param _performanceFeeProceedsBps The performance fee for proceeds tokens, in basis points, taken on each profitable withdrawal.
    /// @param _symbol The symbol of the share token.
    /// @param _name The name of the share token.
    constructor(
        address _depositToken,
        address _proceedsToken,
        address _manager,
        IVaultAccountant _accountant,
        uint256 _performanceFeeBps,
        uint256 _performanceFeeProceedsBps,
        string memory _symbol,
        string memory _name
    ) {
        depositToken = _depositToken;
        proceedsToken = _proceedsToken;
        manager = _manager;
        accountant = _accountant;
        performanceFeeBps = _performanceFeeBps;
        performanceFeeProceedsBps = _performanceFeeProceedsBps;
        totalSupply = 1_000_000;
        symbol = _symbol;
        name = _name;
    }

    /*//////////////////////////////////////////////////////////////
                             TOKEN METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the number of decimals in the share token.
    /// @dev If the deposit token does not implement decimals(), returns 0.
    /// @return The number of decimals in the share token
    function decimals() external view returns (uint8) {
        try IERC20Metadata(depositToken).decimals() returns (uint8 _decimals) {
            return _decimals;
        } catch {
            return 0;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  AUTH
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier that restricts access to only the manager.
    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /// @notice Sets the manager.
    /// @dev Can only be called by the owner.
    /// @param _newManager The new manager.
    function setManager(address _newManager) external onlyOwner {
        address oldManager = manager;
        manager = _newManager;
        emit ManagerUpdated(oldManager, _newManager);
    }

    /// @notice Sets the accountant.
    /// @dev Can only be called by the owner.
    /// @param _newAccountant The new accountant.
    function setAccountant(IVaultAccountant _newAccountant) external onlyOwner {
        IVaultAccountant oldAccountant = accountant;
        accountant = _newAccountant;
        emit AccountantUpdated(oldAccountant, _newAccountant);
    }

    /// @notice Sets the wallet that receives the performance fee.
    /// @dev Can only be called by the owner.
    /// @param _newFeeWallet The new fee wallet.
    function setFeeWallet(address _newFeeWallet) external onlyOwner {
        address oldFeeWallet = feeWallet;
        feeWallet = _newFeeWallet;
        emit FeeWalletUpdated(oldFeeWallet, _newFeeWallet);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT/REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests a deposit of assets.
    /// @param assets The amount of assets to deposit
    function requestDeposit(uint128 assets) external {
        uint256 currentEpoch = depositEpoch;

        queuedDeposit[msg.sender][currentEpoch] += assets;

        depositEpochState[currentEpoch].assetsDeposited += assets;

        SafeTransferLib.safeTransferFrom(depositToken, msg.sender, address(this), assets);

        emit DepositRequested(msg.sender, assets);
    }

    /// @notice Requests a withdrawal of shares.
    /// @param shares The amount of shares to withdraw
    function requestWithdrawal(uint128 shares) external {
        _requestWithdrawal(msg.sender, shares, 0, false);
    }

    /// @notice Requests a withdrawal of shares.
    /// @param shares The amount of shares to withdraw
    /// @param ratioX64 The fraction of the requested shares that will be distributed in proceeds tokens
    function requestWithdrawal(uint128 shares, uint128 ratioX64) external {
        _requestWithdrawal(msg.sender, shares, ratioX64, false);
    }

    /// @notice Requests a withdrawal of shares from any user and optionally redeposits the assets into the vault upon withdrawal execution.
    /// @param user The user to initiate the withdrawal from
    /// @param shares The amount of shares to withdraw
    /// @param ratioX64 The fraction of the requested shares that will be distributed in proceeds tokens
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    function requestWithdrawalFrom(
        address user,
        uint128 shares,
        uint128 ratioX64,
        bool shouldRedeposit
    ) external onlyManager {
        _requestWithdrawal(user, shares, ratioX64, shouldRedeposit);
    }

    /// @notice Internal function to request a withdrawal of shares.
    /// @param user The user to initiate the withdrawal
    /// @param shares The amount of shares to withdraw
    /// @param ratioX64 The fraction of the requested shares that will be distributed in proceeds tokens
    /// @param shouldRedeposit Whether the assets should be redeposited into the vault upon withdrawal execution
    function _requestWithdrawal(
        address user,
        uint128 shares,
        uint128 ratioX64,
        bool shouldRedeposit
    ) internal {
        uint256 _withdrawalEpoch = withdrawalEpoch;

        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[user][_withdrawalEpoch];

        uint256 previousBasis = userBasis[user];

        uint256 userBalance = balanceOf[user];

        uint256 withdrawalBasis = (previousBasis * shares) / userBalance;

        userBasis[user] = previousBasis - withdrawalBasis;

        queuedWithdrawal[user][_withdrawalEpoch] = PendingWithdrawal({
            amount: pendingWithdrawal.amount + shares,
            basis: uint128(pendingWithdrawal.basis + withdrawalBasis),
            ratioX64: ratioX64,
            shouldRedeposit: pendingWithdrawal.shouldRedeposit || shouldRedeposit
        });

        withdrawalEpochState[_withdrawalEpoch].sharesWithdrawn += shares;

        _burnVirtual(user, shares);

        emit WithdrawalRequested(user, shares, ratioX64, shouldRedeposit);
    }

    /// @notice Cancels a deposit in the current (unfulfilled) epoch.
    /// @dev Can only be called by the manager.
    /// @dev If deposited funds in previous epochs have not been completely fulfilled, the manager can execute those deposits to move the unfulfilled amount to the current epoch.
    /// @param depositor The address that requested the deposit
    function cancelDeposit(address depositor) external onlyManager {
        uint256 currentEpoch = depositEpoch;

        uint256 queuedDepositAmount = queuedDeposit[depositor][currentEpoch];
        queuedDeposit[depositor][currentEpoch] = 0;

        depositEpochState[currentEpoch].assetsDeposited -= uint128(queuedDepositAmount);

        SafeTransferLib.safeTransfer(depositToken, depositor, queuedDepositAmount);

        emit DepositCancelled(depositor, queuedDepositAmount);
    }

    /// @notice Cancels a withdrawal in the current (unfulfilled) epoch.
    /// @dev Can only be called by the manager.
    /// @dev If withdrawn shares in previous epochs have not been completely fulfilled, the manager can execute those withdrawals to move the unfulfilled amount to the current epoch.
    /// @param withdrawer The address that requested the withdrawal
    function cancelWithdrawal(address withdrawer) external onlyManager {
        uint256 currentEpoch = withdrawalEpoch;

        PendingWithdrawal memory currentPendingWithdrawal = queuedWithdrawal[withdrawer][
            currentEpoch
        ];

        queuedWithdrawal[withdrawer][currentEpoch] = PendingWithdrawal({
            amount: 0,
            basis: 0,
            ratioX64: 0,
            shouldRedeposit: false
        });
        userBasis[withdrawer] += currentPendingWithdrawal.basis;

        uint256 epochSharesWithdrawn = withdrawalEpochState[currentEpoch].sharesWithdrawn;
        withdrawalEpochState[currentEpoch].sharesWithdrawn = epochSharesWithdrawn >
            currentPendingWithdrawal.amount
            ? uint128(epochSharesWithdrawn - currentPendingWithdrawal.amount)
            : 0;

        _mintVirtual(withdrawer, currentPendingWithdrawal.amount);

        emit WithdrawalCancelled(withdrawer, currentPendingWithdrawal.amount);
    }

    /// @notice Converts an active pending deposit into shares.
    /// @param user The address that requested the deposit
    /// @param epoch The epoch in which the deposit was requested
    function executeDeposit(address user, uint256 epoch) external {
        if (epoch >= depositEpoch) revert EpochNotFulfilled();

        uint256 queuedDepositAmount = queuedDeposit[user][epoch];
        queuedDeposit[user][epoch] = 0;

        DepositEpochState memory _depositEpochState = depositEpochState[epoch];

        uint256 userAssetsDeposited = Math.mulDiv(
            queuedDepositAmount,
            _depositEpochState.assetsFulfilled,
            _depositEpochState.assetsDeposited
        );

        uint256 sharesReceived = Math.mulDiv(
            userAssetsDeposited,
            _depositEpochState.sharesReceived,
            _depositEpochState.assetsFulfilled == 0 ? 1 : _depositEpochState.assetsFulfilled
        );

        // shares from pending deposits are already added to the supply at the start of every new epoch
        _mintVirtual(user, sharesReceived);

        userBasis[user] += userAssetsDeposited;

        uint256 assetsRemaining = queuedDepositAmount - userAssetsDeposited;

        // move remainder of deposit to next epoch -- unfulfilled assets in this epoch will be handled in the next epoch
        if (assetsRemaining > 0) queuedDeposit[user][epoch + 1] += uint128(assetsRemaining);

        emit DepositExecuted(user, userAssetsDeposited, sharesReceived, epoch);
    }

    /// @notice Converts an active pending withdrawal into assets.
    /// @param user The address that requested the withdrawal
    /// @param epoch The epoch in which the withdrawal was requested
    function executeWithdrawal(address user, uint256 epoch) external {
        if (epoch >= withdrawalEpoch) revert EpochNotFulfilled();

        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[user][epoch];

        WithdrawalEpochState memory _withdrawalEpochState = withdrawalEpochState[epoch];

        // prorated shares to fulfill = amount * fulfilled shares / total shares withdrawn
        uint256 sharesToFulfill = (uint256(pendingWithdrawal.amount) *
            _withdrawalEpochState.sharesFulfilled) / _withdrawalEpochState.sharesWithdrawn;

        // deposit assets to withdraw = prorated shares to withdraw * assets fulfilled / total shares fulfilled
        uint256 depositAssetsToWithdraw = Math.mulDiv(
            Math.mulDiv64(sharesToFulfill, 2 ** 64 - pendingWithdrawal.ratioX64),
            _withdrawalEpochState.depositAssetsReceived,
            _withdrawalEpochState.sharesFulfilled == 0 ? 1 : _withdrawalEpochState.sharesFulfilled
        );

        reservedWithdrawalDepositAssets -= depositAssetsToWithdraw;

        // proceeds assets to withdraw = prorated shares to withdraw * assets fulfilled / total shares fulfilled
        uint256 proceedsAssetsToWithdraw = Math.mulDiv(
            Math.mulDiv64(sharesToFulfill, pendingWithdrawal.ratioX64),
            _withdrawalEpochState.proceedsAssetsReceived,
            _withdrawalEpochState.sharesFulfilled == 0 ? 1 : _withdrawalEpochState.sharesFulfilled
        );

        reservedWithdrawalProceedsAssets -= proceedsAssetsToWithdraw;

        uint256 withdrawnBasis = (uint256(pendingWithdrawal.basis) *
            _withdrawalEpochState.sharesFulfilled) / _withdrawalEpochState.sharesWithdrawn;

        uint256 performanceFee = (uint256(
            Math.max(0, int256(depositAssetsToWithdraw) - int256(withdrawnBasis))
        ) * performanceFeeBps) / 10_000;

        uint256 performanceFeeProceeds = (uint256(
            Math.max(0, int256(proceedsAssetsToWithdraw) - int256(0))
        ) * performanceFeeProceedsBps) / 10_000;

        queuedWithdrawal[user][epoch] = PendingWithdrawal({
            amount: 0,
            basis: 0,
            ratioX64: 0,
            shouldRedeposit: false
        });

        uint256 sharesRemaining = pendingWithdrawal.amount - sharesToFulfill;

        uint256 basisRemaining = pendingWithdrawal.basis - withdrawnBasis;

        // move remainder of withdrawal to next epoch -- unfulfilled shares in this epoch will be handled in the next epoch
        if (sharesRemaining + basisRemaining > 0) {
            PendingWithdrawal memory nextQueuedWithdrawal = queuedWithdrawal[user][epoch + 1];
            queuedWithdrawal[user][epoch + 1] = PendingWithdrawal({
                amount: uint128(nextQueuedWithdrawal.amount + sharesRemaining),
                basis: uint128(nextQueuedWithdrawal.basis + basisRemaining),
                ratioX64: pendingWithdrawal.ratioX64,
                shouldRedeposit: pendingWithdrawal.shouldRedeposit
            });
        }

        if (performanceFee > 0) {
            depositAssetsToWithdraw -= performanceFee;
            SafeTransferLib.safeTransfer(depositToken, feeWallet, uint256(performanceFee));
        }
        if (performanceFeeProceeds > 0) {
            proceedsAssetsToWithdraw -= performanceFeeProceeds;
            SafeTransferLib.safeTransfer(proceedsToken, feeWallet, uint256(performanceFeeProceeds));
        }

        if (pendingWithdrawal.shouldRedeposit) {
            uint256 _depositEpoch = depositEpoch;

            queuedDeposit[user][_depositEpoch] += uint128(depositAssetsToWithdraw);
            depositEpochState[_depositEpoch].assetsDeposited += uint128(depositAssetsToWithdraw);

            emit DepositRequested(user, depositAssetsToWithdraw);
        } else {
            SafeTransferLib.safeTransfer(depositToken, user, depositAssetsToWithdraw);
            if (proceedsAssetsToWithdraw > 0) {
                SafeTransferLib.safeTransfer(proceedsToken, user, proceedsAssetsToWithdraw);
            }
        }

        emit WithdrawalExecuted(
            user,
            sharesToFulfill,
            depositAssetsToWithdraw,
            performanceFee,
            performanceFeeProceeds,
            epoch,
            pendingWithdrawal.shouldRedeposit
        );
    }

    /// @notice Alters a caller's withdrawal request from one that redeposits to one that does not.
    /// @param epoch The epoch of the withdrawal request
    function optOutOfRedeposit(uint256 epoch) external {
        PendingWithdrawal memory pendingWithdrawal = queuedWithdrawal[msg.sender][epoch];

        queuedWithdrawal[msg.sender][epoch] = PendingWithdrawal({
            amount: pendingWithdrawal.amount,
            basis: pendingWithdrawal.basis,
            ratioX64: pendingWithdrawal.ratioX64,
            shouldRedeposit: false
        });

        emit RedepositStatusChanged(msg.sender, epoch, false);
    }

    /*//////////////////////////////////////////////////////////////
                               OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Override transfer to handle basis transfer.
    /// @param to The recipient of the shares
    /// @param amount The amount of shares to transfer
    /// @return success True if the transfer was successful
    function transfer(address to, uint256 amount) public override returns (bool success) {
        _transferBasis(msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    /// @notice Override transferFrom to handle basis transfer.
    /// @param from The sender of the shares
    /// @param to The recipient of the shares
    /// @param amount The amount of shares to transfer
    /// @return success True if the transfer was successful
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool success) {
        _transferBasis(from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    /// @notice Internal function to transfer basis proportionally with share transfers.
    /// @param from The sender of the shares
    /// @param to The recipient of the shares
    /// @param amount The amount of shares being transferred
    function _transferBasis(address from, address to, uint256 amount) internal {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance == 0) return;

        uint256 fromBasis = userBasis[from];

        uint256 basisToTransfer = (fromBasis * amount) / fromBalance;

        userBasis[from] = fromBasis - basisToTransfer;

        // Handle the case where recipient has zero balance to avoid division by zero
        uint256 toBalance = balanceOf[to];
        if (toBalance == 0) {
            userBasis[to] += basisToTransfer;
        } else {
            // reset basis to the lowest average between the sender and receiver to ensure performance fee is not deflated
            userBasis[to] += Math.min(basisToTransfer, (userBasis[to] * amount) / toBalance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Makes an arbitrary function call from this contract.
    /// @dev Can only be called by the manager.
    function manage(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyManager returns (bytes memory result) {
        result = target.functionCallWithValue(data, value);
    }

    /// @notice Makes arbitrary function calls from this contract.
    /// @dev Can only be called by the manager.
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

    /// @notice Fulfills deposit requests.
    /// @dev Can only be called by the manager.
    /// @param assetsToFulfill The amount of assets to fulfill
    /// @param managerInput If provided, an arbitrary input to the accountant contract
    function fulfillDeposits(
        uint256 assetsToFulfill,
        bytes memory managerInput
    ) external onlyManager {
        uint256 currentEpoch = depositEpoch;

        DepositEpochState memory epochState = depositEpochState[currentEpoch];

        uint256 totalAssets = accountant.computeNAV(address(this), depositToken, managerInput) +
            1 -
            epochState.assetsDeposited -
            reservedWithdrawalDepositAssets;

        uint256 _totalSupply = totalSupply;

        uint256 sharesReceived = Math.mulDiv(assetsToFulfill, _totalSupply, totalAssets);

        uint256 assetsRemaining = epochState.assetsDeposited - assetsToFulfill;

        depositEpochState[currentEpoch] = DepositEpochState({
            assetsDeposited: uint128(epochState.assetsDeposited),
            sharesReceived: uint128(sharesReceived),
            assetsFulfilled: uint128(assetsToFulfill)
        });

        currentEpoch++;
        depositEpoch = uint128(currentEpoch);

        depositEpochState[currentEpoch] = DepositEpochState({
            assetsDeposited: uint128(assetsRemaining),
            sharesReceived: 0,
            assetsFulfilled: 0
        });

        totalSupply = _totalSupply + sharesReceived;

        emit DepositsFulfilled(currentEpoch - 1, assetsToFulfill, sharesReceived);
    }

    /// @notice Fulfills withdrawal requests.
    /// @dev Can only be called by the manager.
    /// @param sharesToFulfill The amount of shares to fulfill
    /// @param maxDepositAssetsReceived The maximum amount of deposit assets the manager is willing to disburse
    /// @param maxProceedsAssetsReceived The maximum amount of proceeds assets the manager is willing to disburse
    /// @param managerInput If provided, an arbitrary input to the accountant contract
    function fulfillWithdrawals(
        uint256 sharesToFulfill,
        uint256 maxDepositAssetsReceived,
        uint256 maxProceedsAssetsReceived,
        bytes memory managerInput
    ) external onlyManager {
        uint256 _reservedWithdrawalDepositAssets = reservedWithdrawalDepositAssets;
        uint256 _reservedWithdrawalProceedsAssets = reservedWithdrawalProceedsAssets;

        uint256 totalAssets = accountant.computeNAV(address(this), depositToken, managerInput) +
            1 -
            depositEpochState[depositEpoch].assetsDeposited -
            _reservedWithdrawalDepositAssets;

        uint256 currentEpoch = withdrawalEpoch;

        WithdrawalEpochState memory epochState = withdrawalEpochState[currentEpoch];
        uint256 _totalSupply = totalSupply;

        uint256 assetsReceived = Math.mulDiv(sharesToFulfill, totalAssets, _totalSupply);

        (uint256 depositAssetsReceived, uint256 proceedsAssetsReceived) = accountant
            .getTokenAmountsFromPrice(
                address(this),
                depositToken,
                proceedsToken,
                assetsReceived,
                managerInput
            );

        if (depositAssetsReceived > maxDepositAssetsReceived) revert WithdrawalNotFulfillable();
        if (proceedsAssetsReceived > maxProceedsAssetsReceived) revert WithdrawalNotFulfillable();

        uint256 sharesRemaining = epochState.sharesWithdrawn - sharesToFulfill;

        withdrawalEpochState[currentEpoch] = WithdrawalEpochState({
            sharesWithdrawn: uint128(epochState.sharesWithdrawn),
            depositAssetsReceived: uint128(depositAssetsReceived),
            proceedsAssetsReceived: uint128(proceedsAssetsReceived),
            sharesFulfilled: uint128(sharesToFulfill)
        });

        currentEpoch++;

        withdrawalEpoch = uint128(currentEpoch);

        withdrawalEpochState[currentEpoch] = WithdrawalEpochState({
            depositAssetsReceived: 0,
            proceedsAssetsReceived: 0,
            sharesWithdrawn: uint128(sharesRemaining),
            sharesFulfilled: 0
        });

        totalSupply = _totalSupply - sharesToFulfill;

        reservedWithdrawalDepositAssets = _reservedWithdrawalDepositAssets + depositAssetsReceived;

        emit WithdrawalsFulfilled(currentEpoch - 1, depositAssetsReceived, sharesToFulfill);
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

    receive() external payable {}
}
