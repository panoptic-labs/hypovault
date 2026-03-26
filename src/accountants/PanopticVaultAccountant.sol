// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
// Base
import {Ownable} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
// Libraries
import {Math} from "lib/panoptic-v2-core/contracts/libraries/Math.sol";
import {PanopticMath} from "lib/panoptic-v2-core/contracts/libraries/PanopticMath.sol";
// Interfaces
import {IERC20Partial} from "lib/panoptic-v2-core/contracts/tokens/interfaces/IERC20Partial.sol";
import {IERC4626} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
// Types
import {LeftRightUnsigned} from "lib/panoptic-v2-core/contracts/types/LeftRight.sol";
import {LeftRightSigned} from "lib/panoptic-v2-core/contracts/types/LeftRight.sol";
import {LiquidityChunk} from "lib/panoptic-v2-core/contracts/types/LiquidityChunk.sol";
import {PositionBalance} from "lib/panoptic-v2-core/contracts/types/PositionBalance.sol";
import {TokenId} from "lib/panoptic-v2-core/contracts/types/TokenId.sol";
import {PanopticPoolV2} from "lib/panoptic-v2-core/contracts/PanopticPool.sol";

/// @author Axicon Labs Limited
contract PanopticVaultAccountant is Ownable {
    /// @notice Holds the information required to compute the NAV of a PanopticPool
    /// @param pool The PanopticPool to compute the NAV of
    /// @param token0 The token0 of the pool
    /// @param token1 The token1 of the pool
    /// @param maxPriceDeviation The maximum price deviation allowed for the oracle prices
    struct PoolInfo {
        PanopticPoolV2 pool;
        IERC20Partial token0;
        IERC20Partial token1;
        int24 maxPriceDeviation;
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

    /// @notice An invalid list of ERC4626 vaults was provided for the given vault
    error InvalidERC4626Vaults();

    /// @notice An ERC4626 vault's underlying asset does not match the vault's underlying token
    error ERC4626UnderlyingMismatch();

    /// @notice A pool appears more than once in the pools array
    error DuplicatePool();

    /// @notice An ERC4626 vault duplicates a pool collateral token or appears twice in the array
    error DuplicateERC4626();

    /// @notice Default WETH address for this contract
    /// @dev leave as address(0) if unused
    address public immutable wethAddress;

    /// @notice The hashes for each vault: [0] = poolsHash, [1] = erc4626Hash
    mapping(address vault => bytes32[2] hashes) public vaultHashes;

    /// @notice Whether the list of pools for the vault is locked
    mapping(address vault => bool isLocked) public vaultLocked;

    constructor(address owner, address _wethAddress) Ownable(owner) {
        wethAddress = _wethAddress;
    }

    /// @notice Updates the pools and ERC4626 hashes for a vault, with duplicate detection.
    /// @dev This function can only be called by the owner of the contract.
    /// @dev Reverts if any ERC4626 vault duplicates a pool's collateral token or appears twice in the array.
    /// @param vault The address of the vault to update the hashes for
    /// @param pools The pool info structs for the vault
    /// @param erc4626Vaults The ERC4626 vaults for the vault
    function updateHashes(
        address vault,
        PoolInfo[] calldata pools,
        IERC4626[] calldata erc4626Vaults
    ) external onlyOwner {
        if (vaultLocked[vault]) revert VaultLocked();

        // check for duplicate pools
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (pools[i].pool == pools[j].pool) revert DuplicatePool();
            }
        }

        // check for duplicates: no ERC4626 vault can appear twice or match a pool collateral token
        for (uint256 i = 0; i < erc4626Vaults.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (erc4626Vaults[i] == erc4626Vaults[j]) revert DuplicateERC4626();
            }
            for (uint256 j = 0; j < pools.length; j++) {
                if (
                    address(erc4626Vaults[i]) == address(pools[j].pool.collateralToken0()) ||
                    address(erc4626Vaults[i]) == address(pools[j].pool.collateralToken1())
                ) revert DuplicateERC4626();
            }
        }

        vaultHashes[vault][0] = keccak256(abi.encode(pools));
        vaultHashes[vault][1] = keccak256(abi.encode(erc4626Vaults));
    }

    /// @notice Locks the vault from updating its hashes.
    /// @dev This function can only be called by the owner of the contract.
    /// @param vault The address of the vault to lock
    function lockVault(address vault) external onlyOwner {
        vaultLocked[vault] = true;
    }

    /// @notice Returns the NAV of the portfolio contained in `vault` in terms of its underlying token.
    /// @param vault The address of the vault to value
    /// @param underlyingToken The underlying token of the vault
    /// @param managerInput Input calldata from the vault manager consisting of price quotes from the manager, pool information, and a position list for each pool
    /// @return nav The NAV of the portfolio contained in `vault` in terms of its underlying token
    function computeNAV(
        address vault,
        address underlyingToken,
        bytes calldata managerInput
    ) external view returns (uint256 nav) {
        // loop through Panoptic pools
        (
            ManagerPrices[] memory managerPrices,
            PoolInfo[] memory pools,
            TokenId[][] memory tokenIds,

        ) = abi.decode(managerInput, (ManagerPrices[], PoolInfo[], TokenId[][], IERC4626[]));

        if (keccak256(abi.encode(pools)) != vaultHashes[vault][0]) revert InvalidPools();

        // tracks unique tokens across pools to avoid double-counting balances
        address[] memory collateralTokens = new address[](pools.length * 2);

        // resolves stack too deep error
        address _vault = vault;

        // loop over each pools
        for (uint256 i = 0; i < pools.length; i++) {
            int256 poolExposure0;
            int256 poolExposure1;

            // get exposure from options/tokenIds
            int24 twapTick = pools[i].pool.getTWAP();

            if (Math.abs(managerPrices[i].poolPrice - twapTick) > pools[i].maxPriceDeviation)
                revert StaleOraclePrice();

            {
                PositionBalance[] memory positionBalanceArray;
                {
                    LeftRightUnsigned shortPremium;
                    LeftRightUnsigned longPremium;

                    (shortPremium, longPremium, positionBalanceArray, , ) = pools[i]
                        .pool
                        .getFullPositionsData(_vault, true, tokenIds[i]);

                    poolExposure0 =
                        int256(uint256(shortPremium.rightSlot())) -
                        int256(uint256(longPremium.rightSlot()));
                    poolExposure1 =
                        int256(uint256(shortPremium.leftSlot())) -
                        int256(uint256(longPremium.leftSlot()));
                }
                int24 poolPrice = pools[i].pool.getCurrentTick();

                if (Math.abs(poolPrice - twapTick) > pools[i].maxPriceDeviation)
                    revert StaleOraclePrice();

                uint256 numLegs;
                for (uint256 j = 0; j < tokenIds[i].length; j++) {
                    uint128 positionSize = uint128(PositionBalance.unwrap(positionBalanceArray[j]));
                    if (positionSize == 0) revert IncorrectPositionList();
                    TokenId _tokenId = tokenIds[i][j];
                    uint256 positionLegs = _tokenId.countLegs();

                    for (uint256 k = 0; k < positionLegs; k++) {
                        // skip if leg is a credit/loan
                        if (_tokenId.width(k) != 0) {
                            (uint256 amount0, uint256 amount1) = Math.getAmountsForLiquidity(
                                poolPrice,
                                PanopticMath.getLiquidityChunk(_tokenId, k, positionSize)
                            );

                            if (_tokenId.isLong(k) == 0) {
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
                    }

                    // get raw exercised amounts, handles credits/loans gracefully. Compute as opening (rounds down) = true
                    (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) = PanopticMath
                        .computeExercisedAmounts(_tokenId, positionSize, true);

                    poolExposure0 +=
                        int256(longAmounts.rightSlot()) -
                        int256(shortAmounts.rightSlot());
                    poolExposure1 +=
                        int256(longAmounts.leftSlot()) -
                        int256(shortAmounts.leftSlot());

                    numLegs += positionLegs;
                }
                if (numLegs != pools[i].pool.numberOfLegs(_vault)) revert IncorrectPositionList();
            }

            // set native tokens to 0xEeee... to avoid address(0) clashes
            if (address(pools[i].token0) == address(0))
                pools[i].token0 = IERC20Partial(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
            uint256 token0Exposure;
            uint256 token1Exposure;

            // get exposure from vault balance and collateral tracker/ERC4626
            // do not count the vault balance twice if the same token appears in multiple ERC4626 pools
            {
                // do not skip by default
                bool skipToken0 = false;
                bool skipToken1 = false;

                // optimized for small number of pools
                for (uint256 j = 0; j < collateralTokens.length; j++) {
                    // if the token has already been seen, skip
                    if (collateralTokens[j] == address(pools[i].token0)) skipToken0 = true;
                    if (collateralTokens[j] == address(pools[i].token1)) skipToken1 = true;

                    // if we get to a list of collateralToken that's empty, add that token to the list
                    if (collateralTokens[j] == address(0)) {
                        if (!skipToken0) collateralTokens[j] = address(pools[i].token0);
                        // ensure a gap is not created in the collateralTokens array
                        if (!skipToken1)
                            collateralTokens[j + (skipToken0 ? 0 : 1)] = address(pools[i].token1);
                        break;
                    }
                }

                {
                    // If we do not skip that token, get its balance in the vault
                    // add this to the tokenExposure variable
                    if (!skipToken0)
                        token0Exposure = address(pools[i].token0) ==
                            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
                            ? address(_vault).balance
                            : pools[i].token0.balanceOf(_vault);
                    if (!skipToken1) token1Exposure = pools[i].token1.balanceOf(_vault);

                    // Look at the balance of this collateral token if inside a PanopticPool
                    // Add this to the poolExposure variable
                    uint256 collateralBalance = pools[i].pool.collateralToken0().balanceOf(_vault);
                    poolExposure0 += int256(
                        pools[i].pool.collateralToken0().previewRedeem(collateralBalance)
                    );

                    collateralBalance = pools[i].pool.collateralToken1().balanceOf(_vault);
                    poolExposure1 += int256(
                        pools[i].pool.collateralToken1().previewRedeem(collateralBalance)
                    );
                }
            }

            // convert position & token values to underlying using pool's TWAP
            // If the pool token is not the underlying, it needs to be converted to the underlying.
            // HOWEVER, if the underlying token is WETH and token0 is native ETH (0xEeee), skip conversion (1 ETH == 1 WETH)
            // In that case, poolExposure0 and token0Exposure stay in ETH terms, which are equivalent to WETH
            if (address(pools[i].token0) != underlyingToken) {
                if (
                    !(address(pools[i].token0) ==
                        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) &&
                        underlyingToken == wethAddress)
                ) {
                    if (
                        Math.abs(twapTick - managerPrices[i].token0Price) >
                        pools[i].maxPriceDeviation
                    ) revert StaleOraclePrice();

                    uint160 conversionPrice = Math.getSqrtRatioAtTick(twapTick);

                    poolExposure0 = PanopticMath.convert0to1(poolExposure0, conversionPrice);
                    // Gas-optimisation-wise, it makes sense to gate the token0-to-underlying conversion by the token0Exposure != 0 condition,
                    // even though convert0to1(0) will safely equal 0:
                    // I. skipToken0 will happen any time the token0 of a pool is token0 or 1 of another of the vault's pool.
                    // e.g., if the vault trades two ETH-paired pools, skipToken0 == true for pools[1]
                    // II. additionally, the vault might actually just have a zero balance of raw token0s (e.g. all token0s are currently deposited in CT)
                    // III. convert0to1 costs 228 in the zero-value case, whereas if (token0Exposure != 0) costs 13 gas
                    // IV. so therefore, if we save 1 convert0to1 call per 228/13 ~= 17 checks, its worth it
                    // V. I predict that (I) or (II) will be true > 1/17th of the time, so let's insert the check:
                    if (token0Exposure != 0) {
                        token0Exposure = uint256(
                            PanopticMath.convert0to1(int256(token0Exposure), conversionPrice)
                        );
                    }
                }
            }

            // If the pool token is not the underlying, it needs to be converted to the underlying.
            // no need to check for native ETH because it is always token0 in Uni v4
            if (address(pools[i].token1) != underlyingToken) {
                if (Math.abs(twapTick - managerPrices[i].token1Price) > pools[i].maxPriceDeviation)
                    revert StaleOraclePrice();

                uint160 conversionPrice = Math.getSqrtRatioAtTick(twapTick);

                poolExposure1 = PanopticMath.convert1to0(poolExposure1, conversionPrice);
                // See comment above on if (token0Exposure != 0) for why this makes sense despite convert1to0 safely returning 0 given an input of 0
                if (token1Exposure != 0) {
                    token1Exposure = uint256(
                        PanopticMath.convert1to0(int256(token1Exposure), conversionPrice)
                    );
                }
            }

            // add all quantities to nav
            nav +=
                token0Exposure +
                token1Exposure +
                // debt in pools with negative exposure does not need to be paid back
                uint256(Math.max(poolExposure0 + poolExposure1, 0));
        }

        // loop through every 4626 pools
        {
            (, , , IERC4626[] memory erc4626Vaults) = abi.decode(
                managerInput,
                (ManagerPrices[], PoolInfo[], TokenId[][], IERC4626[])
            );

            // validate ERC4626 vault list
            if (keccak256(abi.encode(erc4626Vaults)) != vaultHashes[_vault][1])
                revert InvalidERC4626Vaults();

            // add ERC4626 vault share values to NAV
            for (uint256 i = 0; i < erc4626Vaults.length; i++) {
                if (erc4626Vaults[i].asset() != underlyingToken) revert ERC4626UnderlyingMismatch();
                uint256 shares = erc4626Vaults[i].balanceOf(_vault);
                nav += erc4626Vaults[i].previewRedeem(shares);
            }
        }

        // underlying cannot be native (0x000/0xeee)
        bool skipUnderlying = false;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            if (collateralTokens[i] == underlyingToken) skipUnderlying = true;
        }
        if (!skipUnderlying) nav += IERC20Partial(underlyingToken).balanceOf(_vault);
    }
}
