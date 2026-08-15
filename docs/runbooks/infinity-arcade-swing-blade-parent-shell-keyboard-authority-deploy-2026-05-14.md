# Infinity Arcade Swing Blade Parent Shell Keyboard Authority Deploy - 2026-05-14

Task ID: `infinity-arcade-swing-blade-parent-shell-keyboard-authority-2026-05-14`
Project: `infinity-arcade-Jay`
Frontend canister: `mprew-viaaa-aaaah-quola-cai`
Backend canister: `pifyq-raaaa-aaaab-agrqq-cai` (not changed)
Implementation commit: `b5675ccf36ea0b510b171c3c037ae4497bc76e05`

## Issue

Jay reported: Play -> Space works; click inside game -> menu music starts but Space stops; click outside popup -> Space works again.

## Fix

- Parent arcade shell is now the keyboard authority during active game sessions.
- Current-iframe focus/interaction signals focus the parent modal shell instead of pushing focus into the iframe.
- Parent key bridge continues forwarding Space/actions to Swing Blade.
- The passive `Click Game to activate keyboard` hint still fades on first current-iframe interaction.
- No backend, canister, payment, scoring, ticket economy, or session accounting logic changed.

## Review

Gmai review artifact: `docs/runbooks/infinity-arcade-swing-blade-parent-shell-keyboard-authority-gmai-review-2026-05-14.md`

Verdict: `APPROVE`

## Gates

Commands run from canonical root:

```powershell
node scripts\validate-swing-blade-input-bridge.mjs
node tmp\extract-html-scripts.cjs
node --check tmp\check-index.mjs
node --check tmp\check-swing-blade.mjs
node scripts\build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
npm run deploy:guard
```

Results:

- Validator: PASS 40/40
- Script extraction: PASS
- Index syntax check: PASS
- Swing Blade syntax check: PASS
- Sanitized frontend payload built: 35 files
- Predeploy check passed for active frontend canister `mprew-viaaa-aaaah-quola-cai`
- Deploy identity guard passed for `mcp-identity`; controller verified on active frontend/backend canisters

## Deploy

Deployed changed frontend assets to `mprew-viaaa-aaaah-quola-cai` using asset canister `store` calls:

- `/index.html` identity + gzip
- `/games/swing-blade/index.html` identity + gzip

All four `store` calls returned `()`.

## Live Verification

Raw live asset SHA verification against local sanitized payload:

- `/index.html`
  - local/live SHA256: `ffb5f3105a493da53eb21a4ac0f480a4c33dd4cc00c3e28ede2708bb5858a193`
  - bytes: `1171344`
  - match: true
- `/games/swing-blade/index.html`
  - local/live SHA256: `e44d7bace4173f1bfc17f09966c60c688b0ddbdbc671825f93b25d9d5df73d66`
  - bytes: `210186`
  - match: true

## Residual Risk

Browser-level iframe focus behavior can still vary. Jay should smoke test the exact repro: Play -> Space starts, then click inside game for music -> Space should still start/play without needing to click outside the popup.
