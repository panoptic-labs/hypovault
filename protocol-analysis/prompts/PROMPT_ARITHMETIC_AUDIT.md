
  Scope restriction (hard):

  - Analyze ONLY files under src/ (recursive).
  - Ignore anything outside src/.
  - If you reference a file outside src/, mark it "out of scope" and do not rely on it for conclusions.

  Objective:
  Exhaustively evaluate all possible integer underflow/overflow, truncation, cast, and arithmetic-boundary risks that can lead to:

  1. value extraction / incorrect settlement / accounting drift
  2. solvency bypass or persistent undercollateralization
  3. strategic/permanent DoS via arithmetic panic/revert

  Assumptions:

  - Full MEV adversary.
  - Adversarial callback surfaces unless proven blocked.
  - Arithmetic edge cases are exploitable unless proven otherwise.
  - Solidity ^0.8 checked math is NOT sufficient proof if unchecked, assembly, casts, packed types, or custom math wrappers are involved.

  Deliverables (strict order):

  A) Arithmetic Attack Surface Map

  1. Enumerate every arithmetic hotspot in src/**:

  - unchecked blocks
  - inline assembly arithmetic/bit ops
  - signed/unsigned transitions
  - narrowing casts (e.g. uint256->uint128/int128/int24/uint24/uint16/uint8)
  - mul/div chains, rounding helpers, fixed-point conversions
  - custom packed structs/bitfields (encode/decode/masks/shifts)

  2. For each hotspot include:

  - file:line
  - expression
  - operand provenance (user input vs derived vs storage vs oracle/external return)
  - direct callers + external entrypoints that can reach it

  B) Per-Hotspot Range Proof
  For every hotspot:

  1. Compute/argue min/max reachable range for each operand.
  2. Decide status:

  - Exploitable
  - DoS-only
  - Safe by invariant
  - Unproven

  3. If safe by invariant, explicitly state the invariant and where it is enforced (file:line).
  4. If unproven, state exactly what missing bound/check prevents proof.

  C) Aggregate vs. Per-User Accounting Consistency

  This section targets bugs that no single-expression analysis can find — bugs that emerge from the interaction between a batch/aggregate code path and a per-user
  code path that both modify the same state.

  TRIAGE RULE: When analyzing drift, always check the SIMPLEST impact path first. A bare subtraction underflow causing a revert in a user-facing function (e.g. cancel, claim, withdraw) is almost always more severe and more likely to be triggered than a multi-epoch extraction chain. Report the simplest path BEFORE exploring amplification or complex attack sequences.

  1. Identify every state variable (mapping, accumulator, counter) that satisfies BOTH:
  (a) written or modified at an AGGREGATE level in one function (e.g. manager/admin batch operation, epoch rollover, fulfillment), AND
  (b) written or modified at a PER-USER level across multiple independent calls in another function (e.g. user-facing execute, claim, cancel, rollover)
  2. For each such pair, answer:
    - Does the aggregate path compute a total T and store it?
    - Does the per-user path compute individual values t_i (for N users) and modify the same variable?
    - Is it mathematically guaranteed that sum(t_i) == T, or can rounding introduce drift?
  3. Specifically examine every "remainder = total - floor(prorated)" pattern:
    - floor(a) + floor(b) <= floor(a + b) — the sum of individually floored values can be LESS than the floor of the sum
    - The complement of a floor is effectively a ceil: x - floor(x * r) = ceil(x * (1-r)) when x*r is not exact
    - Therefore sum(user remainders) can EXCEED the aggregate remainder by up to (N-1) units
    - Trace whether any downstream consumer (cancel, withdraw, next-epoch accounting) subtracts per-user values from the aggregate value, and whether that
  subtraction can underflow

  4. Consumer Enumeration (MANDATORY — mechanical, not narrative)
  For each aggregate variable identified in step 1:
    a. Search the contract for EVERY line containing that variable with `-=`, `- `, or as the minuend of any subtraction.
    b. List each as: file:line, function name, what is being subtracted, source of subtracted value (aggregate path or per-user path).
    c. For each: does the subtracted value originate from the per-user path (e.g. a user's queued amount, a user's computed share)? If yes, mark as DRIFT-EXPOSED.
    d. Do NOT skip this step. Do NOT rely on narrative reasoning about "which paths matter." List ALL subtractions mechanically, then analyze each.

  5. Symmetry Check (MANDATORY)
  For every protection mechanism found anywhere in the contract (saturating subtraction, zero-division guard, cap, clamp, min/max bound):
    a. Identify the analogous operation on the opposite flow (deposit↔withdrawal, mint↔burn, request↔cancel, fulfill↔execute).
    b. Does the analogous operation have the same protection? If not, flag the asymmetry as a finding immediately.
    c. Existing defensive code (saturating subtraction, special-case guards, comments like "prevent underflow") is evidence that the bug class is REAL and was already encountered. Search exhaustively for every analogous path that LACKS the same defense. The presence of a patch on one path and its absence on the symmetric path is a HIGH-confidence finding.

  6. For each identified inconsistency:
    - Compute the maximum drift as a function of N (number of users/iterations)
    - Identify every code path that consumes the drifted variable (using the list from step 4)
    - Determine if the drift causes: underflow revert (DoS), overpayment, underpayment, or permanent accounting corruption
    - For EACH consumer from step 4 that is marked DRIFT-EXPOSED: state whether it uses saturating arithmetic, a guard, or bare subtraction
  7. Status for each finding:
    - Drift-safe: proven that sum(t_i) == T exactly (cite proof)
    - Drift-protected: drift exists but ALL downstream consumers use saturating arithmetic or other guards (cite file:line of EVERY guard)
    - Drift-vulnerable: drift exists and at least one downstream consumer can underflow/overflow/misbehave (cite the unguarded file:line)

  D) Findings (prioritized)
  For each exploitable or DoS issue (from sections B and C):

  - ID
  - Severity
  - Impact class (1/2/3)
  - File:line
  - Vulnerable expression or state inconsistency
  - Why checks fail (or are bypassed)
  - Preconditions
  - Minimal attack sequence (start with the SIMPLEST trigger — a single function call that reverts — before describing multi-step chains)
  - Concrete impact (what balance/accounting/solvency changes)
  - Whether repeatable/loopable for amplification

  E) Contract-wide Arithmetic Invariants
  List required invariants that must always hold, e.g.:

  - conservation relations
  - accumulator monotonicity constraints
  - conversion round-trip bounds
  - packed field range constraints
  - aggregate-vs-per-user sum equalities
  For each invariant:
  - where established
  - where consumed
  - what breaks if violated

  F) Patches + Tests

  1. Minimal patch suggestions for each finding (tight edits only).
  2. Tests:

  - >=3 tests per High finding
  - >=2 per Medium
  - include boundary tests (0, 1, max-1, max, sign boundaries)
  - include sequencing tests around settlement/liquidation/force paths if relevant
  - include multi-user rounding tests: N users executing individually, then verifying aggregate consistency

  3. Add at least 1 fuzz invariant per finding category.

  Review rules:

  - No generic "check overflow" advice.
  - No assumptions without evidence.
  - Every claim must cite exact src/...:line.
  - If a path is uncertain, label "unproven" and show missing link.
  - Be explicit about rounding direction and who benefits.
  - When analyzing rounding, always check BOTH the direct computation AND its complement — if one rounds down, the other effectively rounds up.
