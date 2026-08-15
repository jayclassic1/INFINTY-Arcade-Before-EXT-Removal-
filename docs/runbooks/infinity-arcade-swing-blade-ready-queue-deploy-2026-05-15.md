# Infinity Arcade Swing Blade Ready Queue Deploy - 2026-05-15

## Scope

Frontend-only deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai`.

No backend, ticket, payout, token, or economy changes. Backend canister `pifyq-raaaa-aaaab-agrqq-cai` was not touched.

## Change

- Parent queues first P1-A Space `arcade-key` events while iframe input is not ready.
- Parent replays queued Space events after current iframe sends `arcade-input-ready`.
- Swing Blade sends `arcade-input-ready` after `__swingBladeApplyArcadeKey` exists.

## Review

Gmai verdict: `APPROVE`

Review artifact: `docs/runbooks/infinity-arcade-swing-blade-ready-queue-gmai-review-2026-05-15.md`

## Commit

`3799c61f` - `Queue Swing Blade Space until input ready`

## Predeploy gates

Passed:

- `node scripts\validate-frontend-deploy-artifact-sync.mjs`
- `node scripts\validate-arcade-session-resume.mjs`
- `node scripts\validate-swing-blade-keymap-resilience.mjs`
- `node scripts\validate-swing-blade-input-bridge.mjs`
- `node --check tmp\check-index.mjs`
- `node --check tmp\check-swing-blade.mjs`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai`
- `npm run deploy:guard`

## Deploy result

Stored changed frontend assets with asset canister `store` calls:

- `/index.html` identity + gzip: `()` / `()`
- `/games/swing-blade/index.html` identity + gzip: `()` / `()`

## Live verification

- `/index.html`
  - SHA256: `4f6c6117e19cd90d93a01bdbf1b35a3f96a14e1321e7aa7a6d8f40f04ef7e73b`
  - live/local match: true
  - contains `parent-queue-arcade-key`: true
- `/games/swing-blade/index.html`
  - SHA256: `d90515b0031634a37d60f589f89ad4c28f4bb7f0bd4cd4323a7a93405856e96b`
  - live/local match: true
  - contains `apply-hook-ready`: true

## Test request

Jay should hard-refresh and try Play -> immediate Space several times without clicking the game first.

## Residual risk

This targets the diagnosed readiness race. If a failure remains, the diagnostic panel should now show queue/ready/replay stages to identify whether replay fired and whether the game consumed it.
