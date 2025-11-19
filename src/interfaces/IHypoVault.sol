// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Axicon Labs Limited
interface IHypoVault {
    function cancelDeposit(address depositor) external;

    function cancelDeposit() external;

    function cancelWithdrawal(address withdrawer) external;

    function requestWithdrawalFrom(address user, uint128 shares, bool shouldRedeposit) external;

    function fulfillDeposits(uint256 assetsToFulfill, bytes memory managerInput) external;

    function fulfillWithdrawals(
        uint256 sharesToFulfill,
        uint256 maxAssetsReceived,
        bytes memory managerInput
    ) external;

    function manage(
        address target,
        bytes calldata data,
        uint256 value
    ) external returns (bytes memory result);

    function manage(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external returns (bytes[] memory results);
}
