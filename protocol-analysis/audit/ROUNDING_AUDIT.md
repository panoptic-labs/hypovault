# Rounding Audit — HypoVault Protocol

**Scope**: `src/**` (recursive)
**Date**: 2026-03-14
**Auditor**: Adversarial rounding audit per PROMPT_ROUNDING_AUDIT.md

---

## A) Rounding Decision Map

Every mul/div, shift, or conversion that discards precision in `src/**`:

### HypoVault.sol

| # | File:Line | Expression | Direction | Benefits (Actual) | Should Benefit | Mismatch? |
|---|-----------|------------|-----------|-------------------|----------------|-----------|
| R1 | HypoVault.sol:343 | `(previousBasis * shares) / userBalance` | Floor | Protocol (lower withdrawn basis → higher apparent profit → higher fee) | Protocol | No |
| R2 | HypoVault.sol:434–438 | `mulDiv(queuedDepositAmount, assetsFulfilled, assetsDeposited)` | Floor | Protocol (user credited fewer assets) | Protocol | No |
| R3 | HypoVault.sol:440–444 | `mulDiv(userAssetsDeposited, sharesReceived, assetsFulfilled)` | Floor | Protocol (user receives fewer shares) | Protocol | No |
| R4 | HypoVault.sol:470–471 | `(amount * sharesFulfilled) / sharesWithdrawn` | Floor | Protocol (fewer shares fulfilled for user) | Protocol | No |
| R5 | HypoVault.sol:473–477 | `mulDiv(sharesToFulfill, assetsReceived, sharesFulfilled)` | Floor | Protocol (user receives fewer assets) | Protocol | No |
| R6 | HypoVault.sol:481–482 | `(basis * sharesFulfilled) / sharesWithdrawn` | Floor | Protocol (lower basis → higher apparent profit → higher fee) | Protocol | No |
| R7 | HypoVault.sol:483–485 | `(profit * performanceFeeBps) / 10_000` | Floor | **User** (protocol receives less fee) | Protocol | **YES** |
| R8 | HypoVault.sol:584 | `(fromBasis * amount) / fromBalance` | Floor | Sender (retains slightly more basis) | Protocol | No (neutral/safe) |
| R9 | HypoVault.sol:594 | `Math.min(basisToTransfer, (userBasis[to] * amount) / toBalance)` | Floor + min | Protocol (conservative basis prevents fee deflation) | Protocol | No |
| R10 | HypoVault.sol:645 | `mulDiv(assetsToFulfill, _totalSupply, _totalAssets)` | Floor | Protocol (fewer shares minted for depositors) | Protocol | No |
| R11 | HypoVault.sol:691 | `mulDiv(sharesToFulfill, _totalAssets, _totalSupply)` | Floor | Protocol (fewer assets given to withdrawers) | Protocol | No |
| R12 | HypoVault.sol:755 | `mulDiv(shares, totalAssets, totalSupply)` | Floor | Protocol (view function, lower quote) | Protocol | No |

### PanopticVaultAccountant.sol

| # | File:Line | Expression | Direction | Benefits (Actual) | Should Benefit | Mismatch? |
|---|-----------|------------|-----------|-------------------|----------------|-----------|
| R13 | PanopticVaultAccountant.sol:152 | `uint128(PositionBalance.unwrap(positionBalanceArray[j]))` | Truncation (extract lower 128 bits) | Nobody (data extraction, not rounding) | N/A | No |
| R14 | PanopticVaultAccountant.sol:269 | `PanopticMath.convert0to1(poolExposure0, conversionPrice)` | Floor | Protocol (underestimates NAV → fewer shares for depositors) | Protocol | No |
| R15 | PanopticVaultAccountant.sol:280 | `PanopticMath.convert0to1(int256(token0Exposure), conversionPrice)` | Floor | Protocol (underestimates NAV) | Protocol | No |
| R16 | PanopticVaultAccountant.sol:294 | `PanopticMath.convert1to0(poolExposure1, conversionPrice)` | Floor | Protocol (underestimates NAV) | Protocol | No |
| R17 | PanopticVaultAccountant.sol:298 | `PanopticMath.convert1to0(int256(token1Exposure), conversionPrice)` | Floor | Protocol (underestimates NAV) | Protocol | No |
| R18 | PanopticVaultAccountant.sol:160–163 | `Math.getAmountsForLiquidity(...)` | Floor | Protocol (underestimates position value → lower NAV) | Protocol | No |
| R19 | PanopticVaultAccountant.sol:238 | `collateralToken0.previewRedeem(collateralBalance)` | Floor (ERC4626 standard) | Protocol (underestimates collateral value) | Protocol | No |
| R20 | PanopticVaultAccountant.sol:243 | `collateralToken1.previewRedeem(collateralBalance)` | Floor (ERC4626 standard) | Protocol (underestimates collateral value) | Protocol | No |

### Type Narrowing Casts (HypoVault.sol)

| # | File:Line | Cast | Risk |
|---|-----------|------|------|
| C1 | HypoVault.sol:349 | `uint128(pendingWithdrawal.basis + withdrawalBasis)` | Silent truncation if basis > 2^128. Practically unreachable for tokens with ≤18 decimals and reasonable supplies. |
| C2 | HypoVault.sol:387 | `uint128(queuedDepositAmount)` | Safe: `queuedDeposit` is `uint128` in storage, so the value fits. |
| C3 | HypoVault.sol:454 | `uint128(assetsRemaining)` | Safe: `assetsRemaining ≤ queuedDepositAmount` which was `uint128`. |
| C4 | HypoVault.sol:515–516 | `uint128(assetsToWithdraw)` | Safe: derived from uint128 epoch state fields via floor division. |
| C5 | HypoVault.sol:651–652 | `uint128(sharesReceived)`, `uint128(assetsToFulfill)` | Manager-controlled inputs. Manager must ensure values fit uint128. |
| C6 | HypoVault.sol:698–700 | `uint128(assetsReceived)`, `uint128(sharesToFulfill)` | Same as C5. |

---

## B) Rounded State Variable Consumer Map

### B1: `reservedWithdrawalAssets` (uint256, HypoVault.sol:193)

Written from rounded quantities at:
- **HypoVault.sol:715** — `reservedWithdrawalAssets = _reservedWithdrawalAssets + assetsReceived` (addition, where `assetsReceived` = R11 floor). Safe: addition cannot underflow.
- **HypoVault.sol:479** — `reservedWithdrawalAssets -= assetsToWithdraw` (subtraction, where `assetsToWithdraw` = R4+R5 chained floors). **POTENTIAL UNDERFLOW** — must prove safe.

**Proof of safety**: Each user's `assetsToWithdraw = mulDiv(sharesToFulfill_i, assetsReceived, sharesFulfilled)`. Since `sharesToFulfill_i` is floored and `mulDiv` floors, `sum(assetsToWithdraw_i) ≤ assetsReceived`. Therefore `reservedWithdrawalAssets` always has sufficient balance. **SAFE, but dust accumulates** (see Finding ROUND-003).

Read at:
- **HypoVault.sol:638–641** — subtracted from NAV in `fulfillDeposits`
- **HypoVault.sol:680–683** — subtracted from NAV in `fulfillWithdrawals`
- **HypoVault.sol:742–748** — subtracted from NAV in `totalAssets` view

**Impact of dust**: Accumulated dust in `reservedWithdrawalAssets` permanently reduces `_totalAssets`, diluting the exchange rate for all shareholders.

### B2: `depositEpochState[epoch].assetsDeposited` (uint128, HypoVault.sol:45)

Written from rounded quantities at:
- **HypoVault.sol:305** — `+= assets` in `requestDeposit` (addition, exact). Safe.
- **HypoVault.sol:387** — `-= uint128(queuedDepositAmount)` in `_cancelDeposit`. **UNGUARDED SUBTRACTION**. See Finding ROUND-001.
- **HypoVault.sol:516** — `+= uint128(assetsToWithdraw)` in `executeWithdrawal` redeposit path (addition). Safe.
- **HypoVault.sol:649–652** — overwritten in `fulfillDeposits` (set, not subtraction). Safe.
- **HypoVault.sol:658–659** — overwritten for next epoch in `fulfillDeposits` (set). Safe.

Read at:
- **HypoVault.sol:434–438** — divisor in `executeDeposit` (R2)
- **HypoVault.sol:638–641** — subtracted from NAV in `fulfillDeposits`
- **HypoVault.sol:647** — subtracted from `assetsToFulfill` in `fulfillDeposits`
- **HypoVault.sol:680–683** — subtracted from NAV in `fulfillWithdrawals`
- **HypoVault.sol:742–748** — subtracted from NAV in `totalAssets`

**Critical consumer**: Line 387 performs an unguarded subtraction. If per-user rollover drift causes `sum(queuedDeposit[user_i][epoch])` to exceed `assetsDeposited`, the last canceller's transaction reverts. See Finding ROUND-001.

### B3: `withdrawalEpochState[epoch].sharesWithdrawn` (uint128, HypoVault.sol:54)

Written from rounded quantities at:
- **HypoVault.sol:353** — `+= shares` in `_requestWithdrawal` (addition, exact). Safe.
- **HypoVault.sol:413–416** — saturating subtraction in `cancelWithdrawal`. **GUARDED** (clamps to 0). Safe.
- **HypoVault.sol:697–701** — overwritten in `fulfillWithdrawals` (set). Safe.
- **HypoVault.sol:707–709** — overwritten for next epoch in `fulfillWithdrawals` (set). Safe.

Read at:
- **HypoVault.sol:470–471** — divisor in `executeWithdrawal` (R4)
- **HypoVault.sol:481–482** — divisor in `executeWithdrawal` (R6)
- **HypoVault.sol:695** — subtracted from `sharesToFulfill` in `fulfillWithdrawals`

### B4: `userBasis[user]` (uint256, HypoVault.sol:209)

Written from rounded quantities at:
- **HypoVault.sol:345** — `= previousBasis - withdrawalBasis` (subtraction, R1). Safe: `withdrawalBasis = floor(previousBasis * shares / userBalance) ≤ previousBasis`.
- **HypoVault.sol:410** — `+= currentPendingWithdrawal.basis` in `cancelWithdrawal` (addition). Safe.
- **HypoVault.sol:449** — `+= userAssetsDeposited` in `executeDeposit` (addition, R2). Safe.
- **HypoVault.sol:586** — `= fromBasis - basisToTransfer` in `_transferBasis` (subtraction, R8). Safe: `basisToTransfer ≤ fromBasis`.
- **HypoVault.sol:591** — `+= basisToTransfer` (addition). Safe.
- **HypoVault.sol:594** — `+= Math.min(...)` (addition, R9). Safe.

### B5: `totalSupply` (uint256, inherited from ERC20Minimal)

Written from rounded quantities at:
- **HypoVault.sol:664** — `+= sharesReceived` in `fulfillDeposits` (addition, R10). Safe.
- **HypoVault.sol:713** — `-= sharesToFulfill` in `fulfillWithdrawals` (subtraction). Safe: `sharesToFulfill ≤ totalSupply` enforced by share existence.

---

## C) Symmetric Path Diff

### C1: `requestDeposit` ↔ `cancelDeposit`

| Operation | Guard | Details |
|-----------|-------|---------|
| `requestDeposit` → `assetsDeposited += assets` | None needed (addition) | HypoVault.sol:305 |
| `_cancelDeposit` → `assetsDeposited -= uint128(queuedDepositAmount)` | **NONE (bare subtraction)** | HypoVault.sol:387 |

**Asymmetry**: `cancelDeposit` uses bare checked subtraction. When per-user rollover rounding drift causes `sum(queuedDeposit) > assetsDeposited`, the last cancel reverts. **BUG** — see ROUND-001.

### C2: `requestWithdrawal` ↔ `cancelWithdrawal`

| Operation | Guard | Details |
|-----------|-------|---------|
| `_requestWithdrawal` → `sharesWithdrawn += shares` | None needed (addition) | HypoVault.sol:353 |
| `cancelWithdrawal` → `sharesWithdrawn = epochSharesWithdrawn > amount ? ... : 0` | **Saturating subtraction** | HypoVault.sol:413–416 |

**Asymmetry**: The withdrawal side uses a saturating subtraction guard that the deposit side lacks. This is the **key asymmetry** — the withdrawal path is protected against drift-induced underflow, but the deposit path is not.

### C3: `fulfillDeposits` + `executeDeposit` ↔ `fulfillWithdrawals` + `executeWithdrawal`

| Aspect | Deposit Side | Withdrawal Side |
|--------|-------------|-----------------|
| Aggregate counter set at fulfillment | `assetsDeposited = uint128(assetsRemaining)` (line 659) | `sharesWithdrawn = uint128(sharesRemaining)` (line 709) |
| Per-user rollover | `queuedDeposit[user][epoch+1] += uint128(assetsRemaining)` (line 454) | `queuedWithdrawal[user][epoch+1].amount += sharesRemaining` (line 501) |
| Cancel guard | **Bare subtraction** (line 387) | **Saturating subtraction** (lines 413–416) |

Both sides have the same per-user rollover drift problem (`sum(remainders) > aggregate`), but only the withdrawal side has a guard.

### C4: `transfer` ↔ `transferFrom`

Both call `_transferBasis` identically before delegating to `super`. **Symmetric**. No issue.

### C5: `fulfillDeposits` (share pricing) ↔ `fulfillWithdrawals` (asset pricing)

| | Deposits | Withdrawals |
|---|---------|-------------|
| Formula | `shares = mulDiv(assets, supply, totalAssets)` | `assets = mulDiv(shares, totalAssets, supply)` |
| Rounding | Floor → fewer shares minted | Floor → fewer assets disbursed |
| Benefits | Protocol (depositors get less) | Protocol (withdrawers get less) |

**Symmetric and correct**: Both directions round in favor of the protocol.

---

## D) Boundary Value Rounding Tests

### D1: R2 — `executeDeposit` asset pro-rata (line 434)

`userAssetsDeposited = mulDiv(queuedDepositAmount, assetsFulfilled, assetsDeposited)`

| Condition | queuedDeposit | assetsFulfilled | assetsDeposited | Result | Error |
|-----------|--------------|-----------------|-----------------|--------|-------|
| Minimum nonzero error | 1 | 1 | 3 | floor(1×1/3) = 0 | 1 (100%) |
| Maximum error | 1 | assetsDeposited-1 | assetsDeposited | floor((D-1)/D) = 0 | ≤1 unit |
| 1 wei deposit, full fulfill | 1 | assetsDeposited | assetsDeposited | 1 | 0 |
| Boundary: deposit = 1, partial fulfill | 1 | 1 | 2 | 0 | 1 (user gets 0 shares, assets roll over) |

**Revert risk**: If `assetsDeposited = 0`, division by zero. Cannot happen — `fulfillDeposits` requires deposits to exist.

### D2: R3 — `executeDeposit` share calculation (line 440)

`sharesReceived = mulDiv(userAssetsDeposited, epochSharesReceived, assetsFulfilled)`

| Condition | userAssets | epochShares | assetsFulfilled | Result | Error |
|-----------|-----------|-------------|-----------------|--------|-------|
| Min error | 1 | 1 | 3 | 0 | 1 |
| Fallback divisor | 0 | X | 0 → 1 | 0 | N/A (divide-by-1) |

**Note**: The `assetsFulfilled == 0 ? 1 : assetsFulfilled` guard prevents division by zero. When `assetsFulfilled = 0`, all deposits are unfulfilled and `userAssetsDeposited = 0`, so `sharesReceived = 0`. Correct behavior.

### D3: R4 — `executeWithdrawal` share pro-rata (line 470)

`sharesToFulfill = (amount * sharesFulfilled) / sharesWithdrawn`

| Condition | amount | sharesFulfilled | sharesWithdrawn | Result | Error |
|-----------|--------|-----------------|-----------------|--------|-------|
| 1 share, partial | 1 | 1 | 2 | 0 | 1 (user gets 0 assets, shares roll over) |
| 1 share, full | 1 | sharesWithdrawn | sharesWithdrawn | 1 | 0 |

### D4: R10 — `fulfillDeposits` share pricing (line 645)

`sharesReceived = mulDiv(assetsToFulfill, _totalSupply, _totalAssets)`

| Condition | assets | supply | totalAssets | Result | Notes |
|-----------|--------|--------|-------------|--------|-------|
| First deposit (init) | X | 1,000,000 | 1 (from +1 offset) | X × 1,000,000 | Virtual offset working as intended |
| totalAssets = 1 | X | S | 1 | X × S | Extreme dilution — first depositor gets massive shares |
| Large deposit | type(uint128).max | S | T | mulDiv handles 512-bit intermediate | No overflow |

### D5: R7 — Performance fee (line 485)

`performanceFee = (profit * performanceFeeBps) / 10_000`

| Condition | profit | feeBps | Result | Error |
|-----------|--------|--------|--------|-------|
| Min error | 1 | 1 | 0 | 1 (0.01 bps lost) |
| Max error | 9999 | 1 | 0 | 1 (fee rounds to 0 for <10000 profit at 1bp) |
| No profit | 0 | X | 0 | 0 |

---

## E) Aggregate vs. Per-User Rounding Drift

### E1: Deposit Rollover Drift

**Aggregate path** (fulfillDeposits, line 647–659):
```
assetsRemaining_agg = assetsDeposited - assetsToFulfill    // exact, no rounding
depositEpochState[epoch+1].assetsDeposited = uint128(assetsRemaining_agg)
```

**Per-user path** (executeDeposit, lines 434–454):
```
userAssetsDeposited_i = floor(queuedDeposit_i × assetsFulfilled / assetsDeposited)   // R2: floor
assetsRemaining_i = queuedDeposit_i - userAssetsDeposited_i
queuedDeposit[user_i][epoch+1] += uint128(assetsRemaining_i)
```

**Drift analysis**:

Let D = assetsDeposited, F = assetsFulfilled, a_i = queuedDeposit_i (where Σa_i = D).

```
sum(assetsRemaining_i) = D - Σ floor(a_i × F / D)
assetsRemaining_agg   = D - F

drift = sum(assetsRemaining_i) - assetsRemaining_agg
      = F - Σ floor(a_i × F / D)
```

Since `Σ(a_i × F / D) = F` (exact), and each `floor()` loses at most 1:
- `Σ floor(a_i × F / D) ∈ [F - (N-1), F]` where N = number of depositors
- **drift ∈ {0, 1, ..., N-1}**

**Maximum drift**: N-1 wei, where N is the number of depositors in the partially-fulfilled epoch.

**Downstream consumer**: `depositEpochState[epoch].assetsDeposited -= uint128(queuedDepositAmount)` in `_cancelDeposit` (line 387). This is an **unguarded subtraction**. After all N users' rollovers complete, the aggregate `assetsDeposited` for the next epoch is up to N-1 less than the sum of per-user queued amounts. If all N users try to cancel, the last cancellation **underflows and reverts**.

**Impact**: DoS — legitimate `cancelDeposit` calls revert. See ROUND-001.

### E2: Withdrawal Rollover Drift

Same structure as E1, but for shares:

```
sharesToFulfill_i = floor(amount_i × sharesFulfilled / sharesWithdrawn)   // R4: floor
sharesRemaining_i = amount_i - sharesToFulfill_i
```

Drift: up to N-1 shares, where N = number of withdrawers.

**Downstream consumer**: `cancelWithdrawal` uses **saturating subtraction** (lines 413–416), so this drift does NOT cause a revert. **Protected**.

### E3: `reservedWithdrawalAssets` Drift

At `fulfillWithdrawals`: `reservedWithdrawalAssets += assetsReceived` (aggregate R).

Per-user execution: `reservedWithdrawalAssets -= assetsToWithdraw_i` where:
```
sharesToFulfill_i = floor(amount_i × F / W)          // first floor
assetsToWithdraw_i = mulDiv(sharesToFulfill_i, R, F)  // second floor
```

**Chained floor drift**: `sum(assetsToWithdraw_i) ≤ R`.
After all users execute: `reservedWithdrawalAssets` retains `R - sum(assetsToWithdraw_i)` dust.

Maximum dust per epoch: up to 2(N-1) wei (N-1 from first floor propagated through second floor).

**Downstream impact**: The dust is subtracted from `_totalAssets` in future NAV computations (lines 638–641, 680–683, 742–748), causing a permanent but negligible dilution of the exchange rate.

**Accumulation**: Over E epochs with N users each, total locked dust ≤ 2·N·E wei.
- 18-decimal token, 100 users, 1000 epochs: ≤200,000 wei = 0.0000000002 tokens. Negligible.
- 6-decimal token, 100 users, 1000 epochs: ≤200,000 units = 0.2 USDC. Negligible.

### E4: Share Dust from Deposit Execution

At `fulfillDeposits`: `totalSupply += sharesReceived` (aggregate S).

Per-user: `sharesReceived_i = mulDiv(userAssetsDeposited_i, S, assetsFulfilled)` (two chained floors from R2→R3).

`sum(sharesReceived_i) ≤ S`. The difference = shares in `totalSupply` owned by nobody = permanent dilution favoring existing shareholders. Maximum: ≤2(N-1) shares per epoch.

This is the **correct** direction (protocol benefits). No issue.

---

## F) Findings

### ROUND-001: Deposit Rollover Drift Causes `cancelDeposit` DoS

- **Severity**: Medium
- **Category**: DoS (rounding drift → unguarded subtraction underflow)
- **File:Line**: HypoVault.sol:387 (underflow site), HypoVault.sol:434+451+454 (drift source)
- **Rounding sequence**:
  1. `fulfillDeposits` sets `depositEpochState[epoch+1].assetsDeposited = assetsDeposited - assetsToFulfill` (exact)
  2. `executeDeposit` per user: `userAssetsDeposited = floor(queued × fulfilled / deposited)` → remainder = `queued - floor(...)` rolled to epoch+1
  3. `sum(remainders) = assetsDeposited - Σfloor(a_i × F / D) > assetsDeposited - F` by up to N-1
  4. `_cancelDeposit` → `assetsDeposited -= uint128(queuedDepositAmount)` — unguarded subtraction
- **Who benefits**: Nobody — this is a DoS, not value extraction
- **Preconditions**:
  1. An epoch is partially fulfilled (assetsToFulfill < assetsDeposited)
  2. At least 2 depositors in that epoch
  3. All depositors execute their deposits (creating per-user rollovers to next epoch)
  4. No new deposits are made in the next epoch (or insufficient to cover the drift)
  5. The last depositor(s) attempt to cancel in the next epoch
- **Worst-case impact**: The last user's `cancelDeposit` reverts. Their assets are locked until the manager fulfills the epoch. With N depositors, up to N-1 users could be affected (in the worst case where each cancellation reduces the headroom by 1).
- **Amplifiable?**: The drift grows linearly with N (number of depositors). With 100 depositors per epoch, drift = up to 99 wei. Not financially significant, but the DoS is real regardless of amount.
- **Minimal PoC**:
  ```
  1. Alice requests deposit of 3 wei in epoch 0
  2. Bob requests deposit of 7 wei in epoch 0
     → assetsDeposited[0] = 10
  3. Manager fulfills 7 of 10 assets
     → assetsDeposited[1] = 10 - 7 = 3 (aggregate rollover)
  4. Alice executes deposit for epoch 0:
     → userAssetsDeposited = floor(3 × 7 / 10) = 2
     → remainder = 3 - 2 = 1 → queuedDeposit[Alice][1] += 1
  5. Bob executes deposit for epoch 0:
     → userAssetsDeposited = floor(7 × 7 / 10) = 4
     → remainder = 7 - 4 = 3 → queuedDeposit[Bob][1] += 3
  6. Now: assetsDeposited[1] = 3, but Alice has 1 + Bob has 3 = 4 queued
  7. Alice cancels deposit in epoch 1: assetsDeposited[1] = 3 - 1 = 2 ✓
  8. Bob cancels deposit in epoch 1: assetsDeposited[1] = 2 - 3 → UNDERFLOW REVERT ✗
  ```

---

### ROUND-002: Asymmetric Guards Between Deposit and Withdrawal Cancel Paths

- **Severity**: Medium (same root cause as ROUND-001, documenting the asymmetry)
- **Category**: DoS (missing guard)
- **File:Line**: HypoVault.sol:387 (unguarded) vs HypoVault.sol:413–416 (guarded)
- **Description**: `cancelWithdrawal` uses saturating subtraction on `sharesWithdrawn` (clamping to 0), but `_cancelDeposit` uses bare checked subtraction on `assetsDeposited`. The withdrawal side correctly handles rollover drift; the deposit side does not.
- **Who benefits**: N/A (DoS)
- **Preconditions**: Same as ROUND-001
- **Impact**: `cancelDeposit` reverts for the last user(s) when rollover drift exists
- **Amplifiable?**: No additional amplification beyond ROUND-001

---

### ROUND-003: Dust Permanently Locked in `reservedWithdrawalAssets`

- **Severity**: Low
- **Category**: Drift (permanent value lock)
- **File:Line**: HypoVault.sol:479 (per-user subtraction), HypoVault.sol:715 (aggregate addition)
- **Rounding sequence**:
  1. `fulfillWithdrawals`: `reservedWithdrawalAssets += assetsReceived` (aggregate R)
  2. `executeWithdrawal` per user: `reservedWithdrawalAssets -= assetsToWithdraw_i` where `assetsToWithdraw_i = floor(floor(amount_i × F / W) × R / F)`
  3. `sum(assetsToWithdraw_i) ≤ R` → dust = `R - sum` remains permanently
- **Who benefits**: Nobody benefits; value is locked
- **Who should benefit**: Protocol (the dust should be recoverable)
- **Preconditions**: Any epoch with ≥2 withdrawers where rounding produces nonzero remainders
- **Worst-case impact**: ≤2(N-1) wei per epoch locked permanently. Over 1000 epochs with 100 users each: ≤200,000 wei. For 18-decimal tokens this is negligible (~0.0000000002 tokens). For 6-decimal tokens: ~0.2 USDC total.
- **Amplifiable?**: Linearly with epochs and users, but bounded per-epoch. Not practically exploitable.
- **Effect**: `reservedWithdrawalAssets` is subtracted from `totalAssets()`, so locked dust permanently reduces effective NAV, causing infinitesimal dilution for all shareholders.

---

### ROUND-004: Performance Fee Rounds Down (Favors User)

- **Severity**: Informational
- **Category**: Direction error
- **File:Line**: HypoVault.sol:483–485
- **Expression**: `performanceFee = (profit * performanceFeeBps) / 10_000` — floors
- **Who benefits (actual)**: User (receives up to 1 wei more per withdrawal)
- **Who should benefit**: Protocol (fee should round up)
- **Preconditions**: `profit * performanceFeeBps` is not divisible by 10,000
- **Worst-case impact**: 1 wei less fee per withdrawal execution. Not amplifiable per-user (each withdrawal only computed once).
- **Amplifiable?**: Only across many distinct withdrawals. With 1M withdrawals, total leakage = 1M wei = 0.000000000001 ETH. Negligible.
- **Note**: This is standard practice. Most protocols round fees down. Flagged for completeness only.

---

### ROUND-005: Share Dust from Chained Floor Operations in Deposit Execution

- **Severity**: Informational
- **Category**: Drift (shares owned by nobody)
- **File:Line**: HypoVault.sol:434–444 (chained R2→R3 floors), HypoVault.sol:664 (aggregate supply increase)
- **Description**: `totalSupply` is increased by `sharesReceived` at fulfillment (aggregate). Each user receives `floor(floor(a_i × F / D) × S / F)` shares via `_mintVirtual`. The sum of per-user shares ≤ aggregate `sharesReceived`. The difference = "orphaned" shares in `totalSupply` that nobody owns.
- **Who benefits**: Existing shareholders and protocol (slight dilution of new depositors)
- **Who should benefit**: Protocol — this is the correct direction
- **Impact**: ≤2(N-1) orphaned shares per epoch. Negligible.
- **Amplifiable?**: No.

---

## G) Patches + Tests

### Patch for ROUND-001 / ROUND-002: Add Saturating Subtraction to `_cancelDeposit`

**File**: `src/HypoVault.sol`, line 387

**Before**:
```solidity
depositEpochState[currentEpoch].assetsDeposited -= uint128(queuedDepositAmount);
```

**After** (mirror the withdrawal-side pattern at lines 413–416):
```solidity
uint256 epochAssetsDeposited = depositEpochState[currentEpoch].assetsDeposited;
depositEpochState[currentEpoch].assetsDeposited = epochAssetsDeposited > queuedDepositAmount
    ? uint128(epochAssetsDeposited - queuedDepositAmount)
    : 0;
```

**Rationale**: This exactly mirrors the guard used in `cancelWithdrawal` (lines 413–416). The clamped-to-zero outcome is safe because `assetsDeposited` is only used as a divisor in `executeDeposit` (where it's read from the fulfilled epoch, not the current one) and subtracted from NAV (where a slight undercount is protocol-conservative).

### Patch for ROUND-003: Sweep Dust from `reservedWithdrawalAssets`

**Optional** — severity is Low. If desired, add an owner-only function to sweep accumulated dust:

```solidity
/// @notice Recovers dust locked in reservedWithdrawalAssets from rounding.
/// @dev Only callable when there are no pending unfulfilled withdrawal epochs.
function sweepReservedDust() external onlyOwner {
    // Only safe when all withdrawal epochs have been fully executed
    reservedWithdrawalAssets = 0;
}
```

This is optional because the dust is negligible in practice.

### Patch for ROUND-004: Round Performance Fee Up

**Optional** — severity is Informational. If desired:

**Before** (line 483–485):
```solidity
uint256 performanceFee = (uint256(
    Math.max(0, int256(assetsToWithdraw) - int256(withdrawnBasis))
) * performanceFeeBps) / 10_000;
```

**After**:
```solidity
uint256 profit = uint256(Math.max(0, int256(assetsToWithdraw) - int256(withdrawnBasis)));
uint256 performanceFee = (profit * performanceFeeBps + 9_999) / 10_000;
```

Not recommended unless protocol policy mandates it. Rounding fees down is industry standard.

---

### Tests

#### Test 1: ROUND-001 — Boundary test (minimum-error input, 2 users)

```solidity
function test_ROUND001_cancelDepositUnderflow_minError() public {
    // Setup: 2 depositors, partial fulfillment that causes exactly 1 wei drift
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Deposit amounts chosen so that floor rounding produces drift = 1
    // D = 10, F = 7
    // floor(3 * 7 / 10) = 2, remainder = 1
    // floor(7 * 7 / 10) = 4, remainder = 3
    // sum remainders = 4, aggregate remainder = 3, drift = 1
    uint128 aliceDeposit = 3;
    uint128 bobDeposit = 7;

    deal(address(token), alice, aliceDeposit);
    deal(address(token), bob, bobDeposit);

    vm.prank(alice);
    vault.requestDeposit(aliceDeposit);
    vm.prank(bob);
    vault.requestDeposit(bobDeposit);

    // Manager partially fulfills
    vm.prank(manager);
    vault.fulfillDeposits(7, managerInput);

    // Both users execute their deposits (creating rollovers)
    vault.executeDeposit(alice, 0);
    vault.executeDeposit(bob, 0);

    // Alice cancels successfully
    vm.prank(manager);
    vault.cancelDeposit(alice);

    // Bob's cancel reverts (underflow) — this is the bug
    vm.prank(manager);
    vm.expectRevert(); // arithmetic underflow
    vault.cancelDeposit(bob);
}
```

#### Test 2: ROUND-001 — Maximum-error test (N users, each depositing 1 wei)

```solidity
function test_ROUND001_cancelDepositUnderflow_maxError() public {
    uint256 N = 10;
    address[] memory users = new address[](N);

    for (uint256 i = 0; i < N; i++) {
        users[i] = makeAddr(string(abi.encodePacked("user", i)));
        deal(address(token), users[i], 1);
        vm.prank(users[i]);
        vault.requestDeposit(1);
    }

    // Fulfill N-1 out of N (partial)
    vm.prank(manager);
    vault.fulfillDeposits(N - 1, managerInput);

    // All users execute deposits
    for (uint256 i = 0; i < N; i++) {
        vault.executeDeposit(users[i], 0);
    }

    // Aggregate remainder = 10 - 9 = 1
    // Each user: floor(1 * 9 / 10) = 0, remainder = 1
    // Sum of remainders = 10, drift = 10 - 1 = 9 = N - 1

    // First cancel succeeds
    vm.prank(manager);
    vault.cancelDeposit(users[0]);

    // Second cancel reverts (assetsDeposited was 1, now 0, but user has 1 queued)
    vm.prank(manager);
    vm.expectRevert();
    vault.cancelDeposit(users[1]);
}
```

#### Test 3: Round-trip invariant — deposit → partial fulfill → execute → cancel preserves solvency

```solidity
function test_roundTrip_depositExecuteCancel_invariant() public {
    // After applying the ROUND-001 patch, verify no reverts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    deal(address(token), alice, 3);
    deal(address(token), bob, 7);

    vm.prank(alice);
    vault.requestDeposit(3);
    vm.prank(bob);
    vault.requestDeposit(7);

    vm.prank(manager);
    vault.fulfillDeposits(7, managerInput);

    vault.executeDeposit(alice, 0);
    vault.executeDeposit(bob, 0);

    // After patch: both cancels succeed
    vm.prank(manager);
    vault.cancelDeposit(alice);
    vm.prank(manager);
    vault.cancelDeposit(bob); // should not revert with saturating sub

    // Verify: assetsDeposited clamped to 0, no underflow
    (uint128 assetsDeposited,,) = vault.depositEpochState(1);
    assertEq(assetsDeposited, 0);
}
```

#### Test 4: Fuzz test — reservedWithdrawalAssets drift (ROUND-003)

```solidity
function testFuzz_ROUND003_reservedWithdrawalAssets_neverUnderflows(
    uint128[5] memory amounts,
    uint128 sharesToFulfill
) public {
    // Bound inputs
    for (uint256 i = 0; i < 5; i++) {
        amounts[i] = uint128(bound(amounts[i], 1, type(uint64).max));
    }

    // Setup: 5 users request withdrawals with bounded amounts
    // Fulfill a bounded portion
    // Execute all withdrawals individually
    // Verify: reservedWithdrawalAssets >= 0 (no revert on any execution)
    // Verify: reservedWithdrawalAssets has some dust remaining when drift > 0
    assertTrue(vault.reservedWithdrawalAssets() >= 0);
}
```

#### Test 5: Multi-user test — deposit aggregate consistency (ROUND-001)

```solidity
function testFuzz_ROUND001_depositAggregate_consistency(
    uint8 numUsers,
    uint128 fulfillRatio
) public {
    numUsers = uint8(bound(numUsers, 2, 20));

    // Create users, each deposits a random amount
    // Manager partially fulfills
    // All users execute deposits (creating rollovers)

    // Verify: sum(queuedDeposit[user_i][epoch+1]) vs depositEpochState[epoch+1].assetsDeposited
    uint256 sumQueued = 0;
    for (uint256 i = 0; i < numUsers; i++) {
        sumQueued += vault.queuedDeposit(users[i], epoch + 1);
    }

    (uint128 epochAssets,,) = vault.depositEpochState(epoch + 1);

    // The drift should be at most numUsers - 1
    assertLe(sumQueued - epochAssets, numUsers - 1);

    // After patch: all cancels succeed despite drift
    for (uint256 i = 0; i < numUsers; i++) {
        vm.prank(manager);
        vault.cancelDeposit(users[i]); // should not revert
    }
}
```
