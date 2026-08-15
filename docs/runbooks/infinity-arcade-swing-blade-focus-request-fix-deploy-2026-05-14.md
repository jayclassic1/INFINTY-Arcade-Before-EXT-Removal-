# Infinity Arcade Swing Blade Focus Request Fix Deploy - 2026-05-14

Task ID: `infinity-arcade-swing-blade-focus-request-fix-2026-05-14`
Project: `infinity-arcade-Jay`
Frontend canister: `mprew-viaaa-aaaah-quola-cai`
Backend canister: `pifyq-raaaa-aaaab-agrqq-cai` (not changed)
Implementation commit: `362cf5e4`

## Issue

Jay reported that clicking inside Swing Blade started menu music, but Space still did not work until clicking outside the game popup. The passive `Click Game to activate keyboard` hint also remained visible.

## Root Cause

The click inside the child iframe could unlock/start Swing Blade audio without reliably focusing the parent iframe element. Clicking outside the iframe hit the parent modal click handler, which focused the iframe, explaining why Space began working only after an outside click.

## Change

- Swing Blade click/touch now calls `activateArcadeInput()`:
  - initializes audio,
  - posts `arcade-focus-request` to the arcade parent,
  - attempts canvas focus.
- Parent accepts `arcade-focus-request` only when `event.source === gameIframe.contentWindow`, then runs `ensureGameIframeFocus()`.
- Parent still dismisses the hint only after `arcade-input-ready` from the current iframe.
- Removed the parent wrapper-click path that could dismiss the hint without true input readiness.
- No backend/canister/economics/session payment logic changed.

## Review

Gmai review artifact: `docs/runbooks/infinity-arcade-swing-blade-focus-request-fix-gmai-review-2026-05-14.md`

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

- `validate-swing-blade-input-bridge`: PASS 38/38
- script extraction: PASS
- `node --check tmp\check-index.mjs`: PASS
- `node --check tmp\check-swing-blade.mjs`: PASS
- sanitized frontend payload built: 35 files
- predeploy check passed for active frontend canister `mprew-viaaa-aaaah-quola-cai`
- deploy identity guard passed for `mcp-identity`; controller verified on active frontend/backend canisters

## Deploy

Deployed changed frontend assets to `mprew-viaaa-aaaah-quola-cai` using asset canister `store` calls:

- `/index.html` identity + gzip
- `/games/swing-blade/index.html` identity + gzip

All four `store` calls returned `()`.

## Live Verification

Raw live asset SHA verification against local sanitized payload:

- `/index.html`
  - local/live SHA256: `b36915dd67d3cfedd2d53e67a62bd3ae78707051f01d42454af953b55a5a6f98`
  - bytes: `1170641`
  - match: true
- `/games/swing-blade/index.html`
  - local/live SHA256: `801ca59b391f72cb5a27266114301cf85b871e60cf81866f5dfb917f5ce72879`
  - bytes: `203643`
  - match: true

## Residual Risk

Browser-level iframe focus can vary by browser. Jay should smoke test: click `PLAY`, click Swing Blade once, press Space without clicking outside the popup. The hint should disappear only once input is actually ready.
