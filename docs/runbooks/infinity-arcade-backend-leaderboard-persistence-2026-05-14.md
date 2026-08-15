# Infinity Arcade Backend Leaderboard Persistence Fix

- Task ID: `infinity-arcade-backend-leaderboard-persistence-2026-05-14`
- Project: `infinity-arcade-Jay`
- Target canister: `pifyq-raaaa-aaaab-agrqq-cai` (backend)
- Deploy status: **not deployed**; backend upgrade/install was not approved for this task.

## Root cause

`preupgrade()` correctly serializes the runtime high-score map into stable storage:

```motoko
leaderboardEntries := Iter.toArray(leaderboards.entries());
```

But `postupgrade()` then reset `leaderboardEntries := []` before lazy hydration could run. Since `hydrateRuntimeStateIfNeeded()` rebuilds the transient `leaderboards` map from stable `leaderboardEntries`, that reset could wipe persisted high-score entries during a backend upgrade. This matches the observed empty `getAllHighScores()` and null Swing Blade `getHighScore("game-1-1777223039629610695")` result after upgrade.

## Fix

Removed the `leaderboardEntries := []` reset from `postupgrade()` and left the other volatile/derived legacy resets intact. `postupgrade()` still recreates transient maps and sets `runtimeStateHydrated := false`; the next hydration can now rebuild `leaderboards` from the preserved stable entries.

A code comment was added beside the remaining legacy resets to document why `leaderboardEntries` must survive postupgrade.

## Other score/session data reviewed

- `paidGameSessionEntries` is serialized in `preupgrade()` and hydrated into `paidGameSessions`; no postupgrade reset was found.
- `ticketJackpotWinEntries` and `ticketJackpotWinTierEntries` are serialized in `preupgrade()` and restored into buffers during hydration; no postupgrade reset was found.
- `gamePayoutConfigEntries` and `gameTicketJackpotConfigV2Entries` are serialized/hydrated; no postupgrade reset was found.
- `gameRawTicketPoolEntries` / `gameBackedTicketPoolEntries` are cleared only inside the existing `migrateLegacyGameTicketPoolsIfNeeded()` migration after runtime maps are rebuilt. That is an existing pool-migration/economics path and was not changed.

No payout/ticket economics were changed.

## Cycle impact

Persisting one high-score entry per game is not cycle-heavy. The data is tiny and only serialized on canister upgrade. The meaningful operational cost/risk is the backend upgrade execution itself, not ongoing gameplay cost.

Historical scores already wiped from stable storage cannot be recovered by this code fix unless they exist in another data source.

## Verification

Scope verification used **manual path-containment fallback** because `verify_write_scope` was unavailable in this runtime. Planned writes resolved under the allowed roots:

- `backend/main.mo`
- `docs/runbooks/infinity-arcade-backend-leaderboard-persistence-2026-05-14.md`

Checks run:

1. Failing guard before patch: searched for `leaderboardEntries := []`; found the postupgrade reset at line 546.
2. Post-patch guard: searched for `leaderboardEntries := []`; no matches.
3. `git diff --check -- backend/main.mo docs/runbooks/infinity-arcade-backend-leaderboard-persistence-2026-05-14.md`

Motoko compile/build was not run because the available backend check path (`backend:mops:check` / `backend:check`) can write toolchain/build cache outside the two allowed write roots, while this task explicitly constrained writes to `backend/main.mo`, `docs/runbooks/*.md`, and `tmp/*`. No backend deploy, install, or upgrade was performed.
