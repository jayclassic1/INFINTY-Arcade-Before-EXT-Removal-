# Ticket Jackpot Phase 0 Implementation Plan

> **For execution:** Use the subagent-driven-development skill to implement this plan. Route each task by its ownership tag.

**Goal:** Quarantine unsafe record/jackpot surfaces before Ticket Jackpot v1 by making paid-session score submission the only player-authoritative high-score path and removing frontend reward-facing reliance on standalone `submitHighScore()`.

**Architecture:** Phase 0 does not add jackpot payouts yet. It tightens the existing score contract: `submitGameScore()` remains the player gameplay finalization path and now updates the game high score atomically after a validated paid session; standalone `submitHighScore()` becomes admin-only/manual compatibility instead of a public player record path. Frontend stops making a second public high-score write after payout, and tests lock the quarantine.

**Tech Stack:** Motoko backend (`backend/main.mo`), single-file vanilla frontend (`index.html`), Node.js static contract tests under `scripts/`, no deploy in this phase without separate human approval.

---

### Task 1: [IAMJ] Backend record-path quarantine

**Files:**
- Modify: `backend/main.mo`

**Step 1: Add an internal leaderboard helper**

Add a small helper near the leaderboard section that updates the top score for a game and returns `true` only when a new record is written.

Expected shape:

```motoko
func recordValidatedHighScore(player : Principal, gameId : Text, score : Nat) : Bool {
  switch (leaderboards.get(gameId)) {
    case null {
      leaderboards.put(gameId, { player = player; score = score; gameId = gameId; timestamp = Time.now() });
      true;
    };
    case (?current) {
      if (score > current.score) {
        leaderboards.put(gameId, { player = player; score = score; gameId = gameId; timestamp = Time.now() });
        true;
      } else {
        false;
      };
    };
  };
};
```

**Step 2: Call the helper from `submitGameScore()`**

After the score passes paid-session validation and result logging, call:

```motoko
let newRecord = recordValidatedHighScore(caller, gameId, score);
```

For Phase 0, keep the public return type unchanged to minimize frontend/backend compatibility risk. Do not add jackpot fields yet.

**Step 3: Make standalone `submitHighScore()` admin-only**

Change `submitHighScore(gameId, score)` so non-admin callers get:

```motoko
#err("Player high scores must be submitted through submitGameScore")
```

Admin callers may still use it for manual correction by calling the same helper.

**Step 4: Preserve stable layout**

Do not add, remove, or reorder stable vars in Phase 0.

**Step 5: Compile/check**

Run:

```powershell
npm run backend:check
```

Expected: backend check passes, or any compile/toolchain blocker is documented without deploying.

---

### Task 2: [IAMJ] Frontend standalone high-score write quarantine

**Files:**
- Modify: `index.html`

**Step 1: Remove the second player-side high-score update**

Inside `endArcadeGame(gameId, score)`, remove the post-payout call to:

```javascript
be.submitHighScore(gameId, BigInt(score))
```

Do not replace it with a jackpot call yet.

**Step 2: Keep user balance/session behavior unchanged**

`endArcadeGame()` should still:
- call `submitGameScore(...)`
- update `S.quarters` and `S.tickets`
- return tickets earned
- close the paid session flow through existing success behavior.

**Step 3: Make record status conservative**

Until backend returns record/jackpot metadata in a later phase, return `newRecord:false` or omit record celebration logic. Do not show jackpot/record payout claims.

---

### Task 3: [IAMJ] Static quarantine tests

**Files:**
- Create: `scripts/test-ticket-jackpot-phase0-quarantine.mjs`
- Modify if needed: `package.json`

**Step 1: Test backend contract text**

Assert `backend/main.mo` contains:
- `recordValidatedHighScore`
- `submitGameScore` calls `recordValidatedHighScore(caller, gameId, score)`
- `submitHighScore` rejects non-admin/manual player use with the exact message above

**Step 2: Test frontend no longer calls standalone player high-score write**

Assert `index.html` does not contain:

```javascript
be.submitHighScore(gameId,BigInt(score))
```

and does still contain:

```javascript
be.submitGameScore(gameId,BigInt(score),BigInt(gameCost),inputHash,BigInt(durationMs))
```

**Step 3: Run tests**

Run:

```powershell
node scripts\test-ticket-jackpot-phase0-quarantine.mjs
node scripts\validate-paid-session-score-flow.mjs
node scripts\test-ticket-payout-config.mjs
node scripts\test-model-a-chain.mjs
```

Expected: all pass.

---

### Task 4: [GMAI] Review Phase 0 changes

**Files:**
- Review: changed backend/frontend/test files
- Evidence: `docs/runbooks/infinity-arcade-ticket-jackpot-phase-0-gmai-review-2026-05-12.md`

**Review scope:**
- No deploy performed.
- No stable var layout change.
- `submitGameScore()` remains the only player-authoritative record path.
- Standalone `submitHighScore()` cannot be used by normal players for reward-bearing records.
- Existing ticket payout/session tests still pass.

Expected verdict: `APPROVE`, `REVISE REQUIRED`, or `BLOCKED`.

---

### Task 5: [JMAI] Commit and report

**Files:**
- Commit only explicit Phase 0 files.

**Step 1: Inspect diff**

Run:

```powershell
git diff -- backend/main.mo index.html scripts/test-ticket-jackpot-phase0-quarantine.mjs package.json docs/plans/2026-05-12-ticket-jackpot-phase-0.md
```

**Step 2: Commit if tests and review pass**

Run explicit staging only:

```powershell
git add backend/main.mo index.html scripts/test-ticket-jackpot-phase0-quarantine.mjs docs/plans/2026-05-12-ticket-jackpot-phase-0.md
git commit -m "Quarantine ticket jackpot record path"
```

**Step 3: Report**

Report commit hash, tests, review verdict, and clearly state: no deploy was performed; deploy still requires human approval.

---

### Task 6: [HUMAN] Later deploy approval gate

**Decision needed:** After Phase 0 passes tests and review, the human must explicitly approve any deployment to backend `pifyq-raaaa-aaaab-agrqq-cai` and/or frontend `mprew-viaaa-aaaah-quola-cai`.

**Success criteria:** Jmai receives a separate deploy approval message naming the target(s). Without that, no deploy occurs.
