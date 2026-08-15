# Infinity Arcade Swing Blade Input Diagnostics Deploy - 2026-05-15

## User approval

Jay approved diagnostic deploy in Discord: `Okay deploy diagnostic`.

## Scope

Frontend-only diagnostic deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai`.

No backend, token, payout, ticket, or economy change. Backend canister `pifyq-raaaa-aaaab-agrqq-cai` was not touched.

## Patch commit

`d8c7b4b5` - `Add Swing Blade input diagnostics`

## Review

Gmai verdict: `APPROVE`

Review artifact: `docs/runbooks/infinity-arcade-swing-blade-input-diagnostics-gmai-review-2026-05-15.md`

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

Deploy identity guard verified `mcp-identity -> 7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae` and controller access on frontend/backend canisters.

## Deploy

Deployed changed frontend assets using asset canister `store` calls:

- `/index.html` identity + gzip
- `/games/swing-blade/index.html` identity + gzip

All four store calls returned `()`.

## Live verification

Raw live asset SHA verification against local sanitized payload:

- `/index.html`
  - local/live SHA256: `bd6e9249cf6e559c0d788ac70aad5865ea48c41b4a9b3f33c37a7c9b10a19496`
  - match: true
  - contains parent `arcadeInputDebug`: true
- `/games/swing-blade/index.html`
  - local/live SHA256: `8c32fbb5553b5db9d3b65897e1ac6cc40ec16926b99c2823764d0fd83afbcacf`
  - match: true
  - contains game `swingBladeInputDebug`: true

## Jay test URL

Use the normal arcade URL with debug enabled:

`https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/?inputDebug=1`

Then enter Swing Blade and press physical Space in the same flows that failed. The bottom-left panel should show the latest input path counters/events.

## Residual risk

This deploy is diagnostic-only. It identifies the failing segment but does not claim to fix physical Space yet.

## Rollback

Frontend-only rollback can restore prior asset versions and redeploy `/index.html` + `/games/swing-blade/index.html`. Backend snapshots are not involved.
