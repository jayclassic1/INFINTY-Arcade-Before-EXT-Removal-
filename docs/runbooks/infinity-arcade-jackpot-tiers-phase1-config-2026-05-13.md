# Infinity Arcade Jackpot Tiers Phase 1 Config

Task: `icp-arcade-jackpot-tiers-phase1-config-20260513`  
Project: `ICP-ARCADE`  
Date: 2026-05-13  
Deploy: **not performed**

## Summary

Implemented the Phase 1 backend/admin contract shape for 3-tier ticket jackpot configuration while preserving the existing single-threshold jackpot behavior as a compatibility gate.

## Changes

- Backend config shape now exposes:
  - `enabled`
  - `lowScoreThreshold`
  - `lowPayoutPercent`
  - `highScoreThreshold`
  - `highPayoutPercent`
  - `newHighScorePayoutPercent`
  - `updatedAt`
- Added upgrade-safe legacy migration:
  - retained old stable `gameTicketJackpotConfigEntries : [(Text, GameTicketJackpotConfigV1)]`
  - appended new stable `gameTicketJackpotConfigV2Entries : [(Text, GameTicketJackpotConfig)]`
  - normalizes old `scoreThreshold` into `lowScoreThreshold`
- Updated `setGameTicketJackpotConfig(...)` to accept all Phase 1 v2 fields with admin-only authorization and validation.
- Updated `getGameTicketJackpotConfig` and `getAllGameTicketJackpotConfigs` to return v2 views, including legacy-normalized configs before hydration.
- Preserved current payout compatibility:
  - `submitGameScore` still gates jackpots on `newRecord && enabled && score >= lowScoreThreshold`
  - no low/high/new-high stacking payout logic was activated in Phase 1
- Updated frontend IDL/admin UI to expose Ticket Jackpot Tiers controls.
- Synced `.deploy/frontend-public/index.html` byte-for-byte with `index.html`.

## Migration defaults

Legacy single-threshold config maps as follows:

- `scoreThreshold` -> `lowScoreThreshold`
- `lowPayoutPercent` -> `JACKPOT_POOL_PERCENT` (`10`, derived from existing `JACKPOT_POOL_BASIS_POINTS = 1000`)
- `highScoreThreshold` -> `0`
- `highPayoutPercent` -> `0`
- `newHighScorePayoutPercent` -> `JACKPOT_POOL_PERCENT` (`10`)

High tier is disabled by default. Percent fields are Phase 1 contract/config shape and are not used for payout stacking until a later phase.

## Verification

Passed:

- `node scripts\test-ticket-jackpot-phase0-quarantine.mjs`
- `node scripts\test-ticket-jackpot-phase1.mjs`
- `node scripts\test-ticket-jackpot-admin-thresholds.mjs`
- `node scripts\test-ticket-jackpot-tiers-phase1-config.mjs`
- `node scripts\validate-paid-session-score-flow.mjs`
- `node scripts\test-ticket-payout-config.mjs`
- `node scripts\test-model-a-chain.mjs`
- `npm run backend:check`

Evidence path: `C:\Users\Jesse\OpenClawEvidence\icp-arcade-jackpot-tiers-phase1-config-20260513`

## Scope note

`verify_write_scope` tool was unavailable, so manual path-containment fallback was used. All planned writes resolved under the allowed write roots. No deploy was performed.

## Gmai review

Gmai review is still pending. Runtime policy denied direct subagent spawn with agentId=gmai (llowed: iamj), so parent orchestration must request the final Gmai verdict before deploy/sign-off.

