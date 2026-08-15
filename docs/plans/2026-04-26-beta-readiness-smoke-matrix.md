# Infinity Arcade Beta Readiness Smoke Matrix

Date: 2026-04-26
Scope: source-only beta readiness and post-deploy smoke verification assets.
Canisters: frontend `mprew-viaaa-aaaah-quola-cai`, backend `pifyq-raaaa-aaaab-agrqq-cai`.

## Source-only release gate

Run before any backend-first / frontend-second deploy attempt:

```powershell
node scripts\validate-beta-readiness.mjs
node scripts\validate-paid-session-score-flow.mjs
node scripts\validate-ticket-pool-frontend.js
node scripts\test-frontend-publish.mjs
```

`validate-beta-readiness.mjs` is intentionally static-only. It must not call live canisters and does not require `dfx`.

## Post-deploy beta smoke matrix

| # | Scenario | Expected result | Notes |
|---|---|---|---|
| 1 | No-token raw start error | Player sees sanitized no-token copy, not raw backend/debug text. | Confirms payment error sanitizer remains active. |
| 2 | One-token paid session | Starting a ticket game charges exactly one session cost and opens the game. | Backend-first deploy must expose `endGameSession` before frontend relies on it. |
| 3 | No double charge on score submit | Score finalization pays tickets when eligible but does not deduct another token. | Compare token balance before start, after start, and after submit. |
| 4 | Submit failure keeps session | If score submit fails, the modal/game session remains open and local state is not marked submitted. | User should be able to retry or force close. |
| 5 | Force close no payout | Force Close calls `endGameSession`, closes the paid session, and awards no tickets. | Ticket balance and backed pool should not increase for the player. |
| 6 | Replay no extra token | Replaying/rerunning inside the same open local session does not call another spend. | Confirms Phase 2 session guard. |
| 7 | New session charges once | After successful submit or force close, starting another session charges exactly once. | Confirms session lifecycle reset. |
| 8 | Empty backed pool pays 0 truthfully | A qualifying score against an empty backed ticket pool returns/presents 0 payout truthfully. | UI copy must state payouts are capped by backed pool and may pay 0. |

## Deployment safety notes

- Do not deploy from a stale `.dfx/ic/canisters/arcade_backend/arcade_backend.did` that lacks `endGameSession`.
- If the static validator warns about stale `.dfx/ic` artifacts, rebuild `arcade_backend` in an ICP-enabled environment before any deploy command can consume generated artifacts.
- This matrix is verification guidance only; it does not authorize deploy or live mutation.
