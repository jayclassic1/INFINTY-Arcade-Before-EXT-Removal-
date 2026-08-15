# Ticket Session Economy Repair Implementation Plan

> **For execution:** Use the subagent-driven-development skill to implement this plan. Route each task by its ownership tag.

**Goal:** Make Infinity Arcade ticket-game play fair, auditable, and beta-ready by fixing paid sessions, score submission, ticket pools, payout copy, and jackpot/percentile system truth.

**Architecture:** Treat game play as one authoritative backend paid-session lifecycle: start once, deduct once, finalize once, or force-close with no payout. Keep ticket payout economics backed-pool-safe, expose accurate read-only audit surfaces, and align frontend copy/UI with what the backend actually supports. Build percentile/jackpot as a later explicit backend feature, not as UI-only promises.

**Tech Stack:** ICP Motoko backend (`backend/main.mo`), single-file frontend (`index.html`), Node validator scripts, ICP asset frontend deploy flow from `.deploy/frontend-public`, backend upgrade only with explicit approval.

---

## Phase 0 — Freeze the Truth Baseline

### Task 1: [JMAI] Confirm canonical target and safety gates

**Files:**
- Inspect: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\CANONICAL.md`
- Inspect: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\README_CANONICAL_DEPLOY.md`
- Evidence: `C:\Users\Jesse\OpenClawEvidence\icp-arcade-paid-session-score-flow-soft-audit-20260426\audit.md`
- Evidence: `C:\Users\Jesse\OpenClawEvidence\icp-arcade-ticket-payout-soft-audit-20260426\audit.md`

**Steps:**
1. Confirm canonical root remains `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`.
2. Confirm frontend canister `mprew-viaaa-aaaah-quola-cai` and backend `pifyq-raaaa-aaaab-agrqq-cai`.
3. Confirm no deploy/backend mutation happens without explicit Jay approval.
4. Record current commit and dirty state.

**Success criteria:** Canonical root, canisters, current commit, and deployment gate are written into implementation evidence.

### Task 2: [IAMJ] Add failing validators for the broken paid-session contract

**Files:**
- Create: `scripts/validate-paid-session-score-flow.mjs`
- Inspect: `index.html`
- Inspect: `backend/main.mo`
- Inspect: `backend/.build/arcade_backend/arcade_backend.did`

**Steps:**
1. Write a validator that fails if `submitGameScore` directly deducts `tokenCost` from `tokens`.
2. Write a validator that requires a backend session close/finalization method to exist in source and DID.
3. Write a validator that fails if frontend marks score submitted / closes after `submitGameScore` returns `err`.
4. Write a validator that requires `insertCoin` or the session-start path to initialize `_gameStartTime`, `_gameInputs`, `_currentGamePlaying`, and `_arcadeSessionState`.
5. Run it and confirm it fails against current source.

**Commands:**
```powershell
node scripts\validate-paid-session-score-flow.mjs
```
Expected: FAIL, proving current double-charge / missing lifecycle risks.

**Success criteria:** Validator fails for the current defects before implementation.

---

## Phase 1 — Backend Paid Session Lifecycle

### Task 3: [IAMJ] Add explicit backend session state

**Files:**
- Modify: `backend/main.mo`
- Update if needed: generated/backend DID after build

**Backend model:**
- Add stable/transient session entries keyed by caller + game id, or by generated session id if low-risk.
- Minimal session shape:
  - player principal
  - gameId
  - tokenCost
  - openedAt
  - status/open flag
- Keep this minimal. Do not add percentile/jackpot state in this phase.

**Steps:**
1. Add stable storage for active session entries without reordering existing stable fields unsafely.
2. Add runtime hydration helpers if needed.
3. Add helper to derive a stable session key from player/game.
4. Add helper to open/replace/close a session safely.
5. Add comments warning that session start is the only token deduction for a paid play.

**Success criteria:** Backend compiles locally or reaches the next explicit compile blocker with exact error captured.

### Task 4: [IAMJ] Make `spendTokensOnGame` start a paid session

**Files:**
- Modify: `backend/main.mo`

**Steps:**
1. Keep current economic side effects in `spendTokensOnGame`: token deduction, creator royalty, ticket pool funding, revenue log.
2. After successful deduction/accounting, mark a paid session open for caller + gameId.
3. If an open session already exists, return a clear error or intentionally replace only if product decision says replay should require closing first. Recommended: return `Session already open`.
4. Return existing token balance result to preserve frontend compatibility.

**Success criteria:** One call to `spendTokensOnGame` deducts once and opens one session.

### Task 5: [IAMJ] Make `submitGameScore` payout-only and consume session

**Files:**
- Modify: `backend/main.mo`

**Steps:**
1. Remove direct token-balance check/deduction from `submitGameScore`.
2. Require an open paid session for caller + gameId.
3. Validate `tokenCost` against the open session or ignore frontend-passed `tokenCost` after checking compatibility.
4. Keep anti-abuse gates: 30s cooldown, 20 plays/hour, 5 trial plays, 2,000/day, 500/round, backed-pool cap.
5. On successful finalization, consume/close the session before or atomically with payout state changes.
6. Return current token balance from `getTokenBalance(caller)`, not a second-deducted value.
7. Ensure duplicate submits fail with `No active paid session` and do not pay twice.

**Success criteria:** `submitGameScore` can never deduct tokens; it can only finalize an already-paid open session once.

### Task 6: [IAMJ] Add Force Close backend method

**Files:**
- Modify: `backend/main.mo`
- Ensure DID includes: `endGameSession` or chosen method name

**Steps:**
1. Add `endGameSession(gameId : Text) : async Result.Result<Text, Text>`.
2. Require authenticated caller.
3. Require existing open session.
4. Close the session with no ticket payout.
5. Return a short friendly success message.

**Success criteria:** Frontend Force Close has a real backend method and does not mutate tickets/pools except closing the session.

---

## Phase 2 — Frontend Session UX Repair

### Task 7: [IAMJ] Initialize frontend session state on actual paid start

**Files:**
- Modify: `index.html`

**Steps:**
1. In `insertCoin(id)`, after successful `spendTokensOnGame`, initialize `_gameStartTime`, `_gameInputs`, `_currentGamePlaying`, and `_arcadeSessionState`.
2. Reuse `startArcadeGame(id)` if it can be safely made non-deducting, or inline the same initialization cleanly.
3. Ensure replaying an existing session does not call `spendTokensOnGame` again.
4. Ensure loading the iframe only happens after backend paid-session start succeeds.

**Success criteria:** Timer/input/session state starts at the same moment as successful paid session start.

### Task 8: [IAMJ] Fix score submit failure behavior

**Files:**
- Modify: `index.html`

**Steps:**
1. In `endArcadeGame`, return an explicit failure object or `null` when backend returns `err`.
2. In `submitLatestScoreAndClose`, only set `_arcadeSessionState.scoreSubmitted=true`, reset session, and close after confirmed backend `ok`.
3. Sanitize any user-facing backend error with `safeGamePaymentErrorMessage`.
4. Keep the modal open after failure so the player can retry or Force Close.

**Success criteria:** A failed score submit cannot silently discard a paid session/run.

### Task 9: [IAMJ] Fix Force Close UI against backend method

**Files:**
- Modify: `index.html`
- Modify: frontend IDL block in `index.html`

**Steps:**
1. Ensure frontend IDL exposes `endGameSession` with the exact backend signature.
2. Keep confirmation when a latest score exists.
3. On success, reset local session and close modal.
4. On failure, show sanitized error and keep the session visible.

**Success criteria:** Force Close cleanly ends an open session with no payout and no raw error body.

---

## Phase 3 — Ticket Payout Truth + UI Alignment

### Task 10: [IAMJ] Align payout copy with current threshold model

**Files:**
- Modify: `index.html`

**Steps:**
1. Remove or hide last-100 percentile copy until backend supports it.
2. Remove or hide ticking jackpot copy until backend supports it.
3. Show the real current score thresholds:
   - 100 = 5 tickets
   - 500 = 15 tickets
   - 1,000 = 40 tickets
   - 2,500 = 100 tickets
   - 5,000 = 250 tickets
   - 10,000 = 500 tickets
4. State that payouts are capped by the game’s backed ticket pool.
5. Keep backed pool public display and raw pool admin-only.

**Success criteria:** UI no longer promises percentile/jackpot mechanics that backend does not have.

### Task 11: [IAMJ] Keep pool funding/payout accounting validators green

**Files:**
- Modify if needed: `scripts/test-model-a-chain.mjs`
- Modify if needed: `scripts/validate-ticket-pool-frontend.js`
- Modify if needed: `scripts/validate-economy-splits.mjs`

**Steps:**
1. Confirm ticket-game spend still credits raw/backed pools at 7 tickets per Token.
2. Confirm score payout drains only backed pool.
3. Confirm public UI reads backed pool only.
4. Confirm admin UI can inspect raw and backed separately.

**Success criteria:** Ticket accounting validators pass after session changes.

---

## Phase 4 — Optional Percentile / Jackpot Build

### Task 12: [HUMAN] Decide whether percentile/jackpot is beta-now or later

**Decision needed:** Choose one:
- **Recommended beta path:** Ship threshold payouts now; build percentile/jackpot later.
- **Bigger build now:** Implement real score history, percentile bands, jackpot growth, jackpot cap, and breaker state before beta.

**Success criteria:** Jay confirms whether jackpot/percentile is Phase 4 now or backlog.

### Task 13: [IAMJ] If approved, design real percentile/jackpot backend

**Files:**
- Modify: `backend/main.mo`
- Modify: `index.html`
- Create validators under `scripts/`

**Minimum backend requirements:**
1. Store recent score history per game.
2. Rank new score against last 100 scores.
3. Define payout percentiles explicitly.
4. Define ticking jackpot growth rule.
5. Cap jackpot at a safe percent of backed pool.
6. Consume backed pool on jackpot payout.
7. Expose query method for score info that actually exists live.

**Success criteria:** UI percentile/jackpot copy is backed by installed backend behavior and tests.

---

## Phase 5 — Review, Build, Deploy Gates

### Task 14: [IAMJ] Run full local validation suite

**Files:**
- All changed files

**Commands:**
```powershell
node scripts\validate-beta-readiness.mjs
node scripts\validate-paid-session-score-flow.mjs
node scripts\test-model-a-chain.mjs
node scripts\test-ticket-pool-visibility.mjs
node scripts\validate-ticket-pool-frontend.js
node scripts\validate-economy-splits.mjs
node scripts\validate-game-payment-error-sanitization.mjs
node scripts\validate-creator-earnings-phase1.mjs
node scripts\validate-creator-earnings-phase2.mjs
node scripts\validate-creator-earnings-phase3.mjs
node scripts\validate-creator-earnings-phase4.mjs
node scripts\test-frontend-publish.mjs
node scripts\validate-wallet-globals.mjs
git diff --check -- index.html backend\main.mo scripts
```

**Success criteria:** All validators pass or each failure is classified as blocker/non-blocker with evidence.

### Task 15: [GMAI] Review session/economy safety

**Files:**
- Review: `backend/main.mo`
- Review: `index.html`
- Review: `scripts/validate-paid-session-score-flow.mjs`
- Evidence destination: `C:\Users\Jesse\OpenClawEvidence\icp-arcade-ticket-session-economy-repair-20260426\gmai-review.md`

**Review focus:**
1. No double charge.
2. No duplicate ticket payout.
3. Force Close cannot pay tickets.
4. Failed submit cannot discard session silently.
5. Public UI does not overpromise unbuilt jackpot/percentile behavior.
6. Raw/backed ticket pool semantics stay separated.

**Success criteria:** Gmai returns `APPROVE`, `REVISE REQUIRED`, or `BLOCKED`.

### Task 16: [HUMAN] Approve backend deployment

**Decision needed:** Backend deployment mutates production code and session logic. Jay must explicitly approve the backend upgrade after review passes.

**Success criteria:** Explicit deploy approval for backend `pifyq-raaaa-aaaab-agrqq-cai`.

### Task 17: [JMAI] Deploy backend only after approval

**Files:**
- Deploy from canonical root only.

**Steps:**
1. Run ICP preflight.
2. Confirm identity/network/canister target.
3. Build backend.
4. Upgrade backend.
5. Verify canister status and core query methods.
6. Record deployed Wasm/build evidence.

**Success criteria:** Backend upgrade completed and health-checked.

### Task 18: [HUMAN] Approve frontend deployment

**Decision needed:** Deploy the corresponding frontend UX/IDL/copy updates to `mprew-viaaa-aaaah-quola-cai`.

**Success criteria:** Explicit frontend deploy approval.

### Task 19: [JMAI] Deploy frontend only after approval

**Files:**
- Build with: `node scripts\build-frontend-publish.mjs`
- Deploy payload: `.deploy\frontend-public`
- Target: `mprew-viaaa-aaaah-quola-cai`

**Steps:**
1. Build sanitized frontend payload.
2. Deploy from `.deploy/frontend-public` only.
3. Verify live `/index.html` hash.
4. Verify live markers for session fix, payout copy, and sanitizer remain present.

**Success criteria:** Live frontend matches approved local build.

---

## Phase 6 — Production Retest Matrix

### Task 20: [JMAI] Manual production smoke test with Jay

**Scenarios:**
1. 1 Token player starts Swing Blade, submits score, is not charged twice.
2. Submit failure keeps game/session open.
3. Force Close closes with no payout and no raw error.
4. Replaying inside one paid session does not spend extra Tokens.
5. New paid session after close spends exactly once.
6. Backed pool at 0 pays 0 tickets cleanly without confusing copy.
7. Once backed pool is funded, qualifying score pays capped tickets and drains backed pool.

**Success criteria:** Evidence screenshot/log notes show each beta-critical path passes.

### Task 21: [JMAI] Publish final beta rule summary

**Deliver to Jay:**
- Player-facing rules.
- Creator/economy rules.
- Admin/reserve rules.
- Known later work: percentile/jackpot if deferred.

**Success criteria:** Jay has a concise operating manual for beta testers.
