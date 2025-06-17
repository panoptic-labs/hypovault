// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
// Base
import {Ownable} from "lib/panoptic-v1.1/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
// Libraries
import {AccountingMath} from "../libraries/AccountingMath.sol";
import {Math} from "lib/panoptic-v1.1/contracts/libraries/Math.sol";
// Interfaces
import {IERC20Partial} from "lib/panoptic-v1.1/contracts/tokens/interfaces/IERC20Partial.sol";
import {IV3CompatibleOracle} from "lib/panoptic-v1.1/contracts/interfaces/IV3CompatibleOracle.sol";
import {PanopticPool} from "lib/panoptic-v1.1/contracts/PanopticPool.sol";
// Types
import {LeftRightUnsigned} from "lib/panoptic-v1.1/contracts/types/LeftRight.sol";
import {LiquidityChunk} from "lib/panoptic-v1.1/contracts/types/LiquidityChunk.sol";
import {PositionBalance} from "lib/panoptic-v1.1/contracts/types/PositionBalance.sol";
import {TokenId} from "lib/panoptic-v1.1/contracts/types/TokenId.sol";

/// @author dyedm1
contract PanopticVaultAccountant is Ownable {
    /// @notice Holds the information required to compute the NAV of a PanopticPool
    /// @param pool The PanopticPool to compute the NAV of
    /// @param token0 The token0 of the pool
    /// @param token1 The token1 of the pool
    /// @param poolOracle The oracle for the pool
    /// @param oracle0 The oracle for token0
    /// @param isToken0Flipped Whether token0 for the pool is token1 in the oracle
    /// @param oracle1 The oracle for token1
    /// @param isToken1Flipped Whether token1 for the pool is token0 in the oracle
    /// @param maxPriceDeviation The maximum price deviation allowed for the oracle prices
    /// @param twapWindow The time window (in seconds)to compute the TWAP over
    struct PoolInfo {
        PanopticPool pool;
        IERC20Partial token0;
        IERC20Partial token1;
        IV3CompatibleOracle poolOracle;
        IV3CompatibleOracle oracle0;
        bool isToken0Flipped;
        IV3CompatibleOracle oracle1;
        bool isToken1Flipped;
        int24 maxPriceDeviation;
        uint32 twapWindow;
    }

    /// @notice Holds the prices provided by the vault manager
    /// @param poolPrice The price of the pool
    /// @param token0Price The price of token0 relative to the underlying
    /// @param token1Price The price of token1 relative to the underlying
    struct ManagerPrices {
        int24 poolPrice;
        int24 token0Price;
        int24 token1Price;
    }

    /// @notice An invalid list of pools was provided for the given vault
    error InvalidPools();

    /// @notice The vault manager provided an incorrect or incomplete position list for one or more pools
    error IncorrectPositionList();

    /// @notice One or more oracle prices are outside the maxPriceDeviation from a price provided by the vault manager
    error StaleOraclePrice();

    /// @notice The pools hash for this vault has been locked and cannot be updated
    error VaultLocked();

    /// @notice The hash of pool structs to query for each vault
    mapping(address vault => bytes32 poolsHash) public vaultPools;

    /// @notice Whether the list of pools for the vault is locked
    mapping(address vault => bool isLocked) public vaultLocked;

    function updatePoolsHash(address vault, bytes32 poolsHash) external onlyOwner {
        if (vaultLocked[vault]) revert VaultLocked();
        vaultPools[vault] = poolsHash;
    }

    /// @notice Locks the vault from updating its pools hash
    function lockVault(address vault) external onlyOwner {
        vaultLocked[vault] = true;
    }

    /// @notice Returns the NAV of the portfolio contained in `vault` in terms of its underlying token
    /// @param vault The address of the vault to value
    /// @param managerInput Additional input from the vault manager to be used in the accounting process, if applicable
    /// @return nav The NAV of the portfolio contained in `vault` in terms of its underlying token
    function computeNAV(
        address vault,
        bytes calldata managerInput
    ) external view returns (uint256 nav) {
        (
            address underlyingToken,
            ManagerPrices[] memory managerPrices,
            PoolInfo[] memory pools,
            TokenId[] memory tokenIds
        ) = abi.decode(managerInput, (address, ManagerPrices[], PoolInfo[], TokenId[]));

        if (keccak256(abi.encode(pools)) != vaultPools[vault]) revert InvalidPools();

        address[] memory underlyingTokens = new address[](pools.length * 2);

        for (uint256 i = 0; i < pools.length; i++) {
            if (
                Math.abs(
                    managerPrices[i].poolPrice -
                        AccountingMath.twapFilter(pools[i].poolOracle, pools[i].twapWindow)
                ) > pools[i].maxPriceDeviation
            ) revert StaleOraclePrice();

            uint256[2][] memory positionBalanceArray;
            int256 poolExposure0;
            int256 poolExposure1;
            {
                LeftRightUnsigned shortPremium;
                LeftRightUnsigned longPremium;

                (shortPremium, longPremium, positionBalanceArray) = pools[i]
                    .pool
                    .getAccumulatedFeesAndPositionsData(vault, true, tokenIds);

                poolExposure0 =
                    int256(uint256(shortPremium.rightSlot())) -
                    int256(uint256(longPremium.rightSlot()));
                poolExposure1 =
                    int256(uint256(longPremium.leftSlot())) -
                    int256(uint256(shortPremium.leftSlot()));
            }

            uint256 numLegs;
            for (uint256 j = 0; j < tokenIds.length; j++) {
                if (positionBalanceArray[j][1] == 0) revert IncorrectPositionList();
                uint256 positionLegs = tokenIds[j].countLegs();
                for (uint256 k = 0; k < positionLegs; k++) {
                    if (positionBalanceArray[j][1] != 0) revert IncorrectPositionList();

                    (uint256 amount0, uint256 amount1) = Math.getAmountsForLiquidity(
                        managerPrices[i].poolPrice,
                        AccountingMath.getLiquidityChunk(
                            tokenIds[j],
                            k,
                            uint128(positionBalanceArray[j][1])
                        )
                    );

                    if (tokenIds[j].isLong(k) == 0) {
                        unchecked {
                            poolExposure0 += int256(amount0);
                            poolExposure1 += int256(amount1);
                        }
                    } else {
                        unchecked {
                            poolExposure0 -= int256(amount0);
                            poolExposure1 -= int256(amount1);
                        }
                    }
                }
                numLegs += positionLegs;
            }
            if (numLegs != tokenIds[i].countLegs()) revert IncorrectPositionList();

            bool skipToken0 = false;
            bool skipToken1 = false;
            for (uint256 j = 0; j < underlyingTokens.length; j++) {
                if (underlyingTokens[j] == address(pools[i].token0)) skipToken0 = true;
                if (underlyingTokens[j] == address(pools[i].token1)) skipToken1 = true;

                if (underlyingTokens[j] == address(0)) {
                    if (!skipToken0)
                        underlyingTokens[j] = address(pools[i].token0) == address(0)
                            ? 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            : address(pools[i].token0);
                    if (!skipToken1) underlyingTokens[j + 1] = address(pools[i].token1);
                    break;
                }
            }

            if (!skipToken0)
                poolExposure0 += address(pools[i].token0) == address(0)
                    ? int256(address(vault).balance)
                    : int256(pools[i].token0.balanceOf(vault));
            if (!skipToken1) poolExposure1 += int256(pools[i].token1.balanceOf(vault));

            uint256 collateralBalance = pools[i].pool.collateralToken0().balanceOf(vault);
            poolExposure0 += int256(
                pools[i].pool.collateralToken0().previewRedeem(collateralBalance)
            );

            collateralBalance = pools[i].pool.collateralToken1().balanceOf(vault);
            poolExposure1 += int256(
                pools[i].pool.collateralToken1().previewRedeem(collateralBalance)
            );

            // convert position values to underlying
            if (address(pools[i].token0) != underlyingToken) {
                int24 conversionPrice = AccountingMath.twapFilter(
                    pools[i].oracle0,
                    pools[i].twapWindow
                );
                if (
                    Math.abs(conversionPrice - managerPrices[i].token0Price) >
                    pools[i].maxPriceDeviation
                ) revert StaleOraclePrice();

                poolExposure0 = pools[i].isToken0Flipped
                    ? AccountingMath.convert1to0(
                        poolExposure0,
                        Math.getSqrtRatioAtTick(conversionPrice)
                    )
                    : AccountingMath.convert0to1(
                        poolExposure0,
                        Math.getSqrtRatioAtTick(conversionPrice)
                    );
            }

            if (address(pools[i].token1) != underlyingToken) {
                int24 conversionPrice = AccountingMath.twapFilter(
                    pools[i].oracle1,
                    pools[i].twapWindow
                );
                if (
                    Math.abs(conversionPrice - managerPrices[i].token1Price) >
                    pools[i].maxPriceDeviation
                ) revert StaleOraclePrice();

                poolExposure1 = pools[i].isToken1Flipped
                    ? AccountingMath.convert1to0(
                        poolExposure1,
                        Math.getSqrtRatioAtTick(conversionPrice)
                    )
                    : AccountingMath.convert0to1(
                        poolExposure1,
                        Math.getSqrtRatioAtTick(conversionPrice)
                    );
            }
            nav += uint256(Math.max(poolExposure0 + poolExposure1, 0));
        }

        bool skipUnderlying = false;
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            if (underlyingTokens[i] == underlyingToken) skipUnderlying = true;
        }
        if (!skipUnderlying) nav += IERC20Partial(underlyingToken).balanceOf(vault);
    }
}
