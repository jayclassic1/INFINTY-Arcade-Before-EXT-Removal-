# Infinity Arcade Model A E2E Review

- Date: 2026-04-23
- Scope: unified root after backend passes 1-3 and frontend integration pass 1
- Reviewer verdict: FAIL
- Slice verdict: not ready for deploy sign-off

## Overall verdict
The backend now has a real backed-vs-raw split and the targeted guardrail scripts pass, but the unified slice is not yet end-to-end ready. The main blockers are a semantic mismatch between gameplay funding and payout economics, plus frontend/backend integration drift in the reserve-funding/admin surfaces.

## What passes
1. `backend/main.mo` now keeps separate raw and backed per-game pools and exposes both query surfaces.
2. `submitGameScore()` fails closed to the backed pool and decrements only the backed pool.
3. Legacy migration is one-way and avoids reconstructing backed balances from raw-only history.
4. Targeted regression scripts pass:
   - `backend/scripts/test-model-a-pass2.mjs`
   - `backend/scripts/test-model-a-pass3.mjs`
   - `scripts/validate-ticket-pool-frontend.js`

## Concrete issues found

### 1) Gameplay funding semantics are not aligned with payout semantics
**Severity:** high

`spendTokensOnGame()` credits `computeTicketGamePoolCredit(amount)`, and that helper currently returns `amount` unchanged. So spending 1 token credits only 1 backed ticket. But `submitGameScore()` can pay up to 500 tickets in one round from the payout table.

That means ordinary play can deplete a game's backed pool almost immediately unless a separate admin funding flow keeps topping it up. For the current Model A slice, this is not a coherent economic path yet.

Relevant code:
- `backend/main.mo:449-456`
- `backend/main.mo:545-577`
- `backend/main.mo:679-771`

### 2) Public game details still present outdated/misleading ticket-pool messaging
**Severity:** medium

The frontend now queries `getGameBackedTicketPool()` successfully, but `openGameDetails()` still tells users that the exact per-game backed amount is not available and only shows the numerical pool values in the admin-only audit strip.

So the UI copy is stale relative to the backend and undercuts the requirement that the public-facing pool view be the backed value surface.

Relevant code:
- `index.html:8976-9020`

### 3) Frontend reserve-funding/admin wiring appears ahead of backend implementation
**Severity:** high

The frontend IDL and admin handlers reference methods such as:
- `getTreasuryLaneConfig`
- `adminFundGameTicketPoolFromDeposit`
- `adminConfirmDirectTicketReserveFunding`

Those names were found in `index.html`, but were not found in `backend/main.mo` during review. That suggests the unified root still has interface drift between frontend expectations and backend source.

If that reading is correct, reserve-funding admin actions are not actually deploy-ready from this root.

Relevant code:
- `index.html:7409-7411`
- `index.html:12472-12522`
- backend source search in `backend/main.mo` returned no matching definitions

### 4) Test coverage is useful but still too structural for sign-off
**Severity:** medium

The added scripts verify that specific code patterns exist, which is helpful as a guard against accidental regression. But they do not prove the full end-to-end behavior of:
- reserve funding
- backed pool growth vs payout drain
- frontend admin funding actions against a live backend
- migration behavior on real legacy state

At this stage they are meaningful smoke checks, not full acceptance coverage.

## Pass/fail against requested review points
1. Public-facing ticket pool shows backed values only: **FAIL**
   - backed query exists, but the public details view still uses stale copy and withholds the numeric backed amount from non-admin users.
2. Admin/raw vs backed separation clear and not misleading: **PARTIAL / FAIL**
   - admin audit separation is present, but public copy and legacy fallback behavior still blur the story.
3. `spendTokensOnGame()` and `submitGameScore()` aligned with Model A semantics: **FAIL**
   - funding credit and payout table are economically inconsistent.
4. Accounting edge-case gaps / migration risks: **PARTIAL**
   - migration is safer now; major remaining gap is the unresolved funding model.
5. Frontend/backend integration mismatches or broken query use: **FAIL**
   - reserve/admin method drift appears unresolved.
6. Tests/scripts meaningful and sufficient for this stage: **PARTIAL / FAIL**
   - useful regressions, insufficient for deploy readiness.

## Recommended next step before deploy
1. Decide and implement the actual Model A conversion between token spend, ICP reserve funding, and backed-ticket credit.
2. Remove or fix frontend calls for reserve/admin methods that are not implemented in `backend/main.mo`, or add the backend methods and verify them live.
3. Update the public game details UI so it explicitly shows the backed pool value to users and keeps raw values admin-only.
4. Add one real integration test path covering: fund reserve -> backed pool increases -> score submission drains backed pool -> UI reflects new backed value.
