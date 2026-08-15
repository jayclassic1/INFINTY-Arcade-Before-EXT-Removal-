# Infinity Arcade Swing Blade Ready Queue Implementation - 2026-05-15

## Scope

Frontend-only fix for intermittent Play -> immediate Space failures diagnosed from Jay's debug screenshots.

No backend, ticket, payout, token, or economy changes.

## Root cause hypothesis

The parent shell sometimes receives and forwards the first Space before Swing Blade has fully armed its `arcade-key` apply hook. In failed screenshots, parent counters showed Space was posted, but no game receive/apply/title-consume events appeared. Successful attempts differed by timing.

## Change

- Parent now resets iframe input readiness whenever a new game iframe is loaded.
- Parent queues P1-A Space `arcade-key` down/up messages while the iframe has not yet reported `arcade-input-ready`.
- Parent still posts immediately as before, but replays queued keys when the current iframe reports ready.
- Swing Blade now reports `arcade-input-ready` after the apply hook exists (`apply-hook-ready`) in addition to focus readiness.
- Diagnostics now include readiness reset, queue, ready, flush, and replay stages.

## Changed files

- `index.html`
- `.deploy/frontend-public/index.html`
- `games/swing-blade/index.html`
- `.deploy/frontend-public/games/swing-blade/index.html`
- `scripts/validate-swing-blade-input-bridge.mjs`
- `scripts/validate-swing-blade-keymap-resilience.mjs`

## Verification

Passed:

- `node scripts\validate-frontend-deploy-artifact-sync.mjs`
- `node scripts\validate-arcade-session-resume.mjs`
- `node scripts\validate-swing-blade-keymap-resilience.mjs`
- `node scripts\validate-swing-blade-input-bridge.mjs`
- `node tmp\extract-html-scripts.cjs`
- `node --check tmp\check-index.mjs`
- `node --check tmp\check-swing-blade.mjs`
- `git diff --check -- index.html .deploy/frontend-public/index.html games/swing-blade/index.html .deploy/frontend-public/games/swing-blade/index.html scripts/validate-swing-blade-input-bridge.mjs scripts/validate-swing-blade-keymap-resilience.mjs`

## Deploy gate

Requires Gmai approval before live deploy.
