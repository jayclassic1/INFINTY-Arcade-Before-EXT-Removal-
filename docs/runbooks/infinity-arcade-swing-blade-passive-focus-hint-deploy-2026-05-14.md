# Infinity Arcade Swing Blade Passive Focus Hint Deploy - 2026-05-14

Task ID: `infinity-arcade-swing-blade-passive-focus-hint-2026-05-14`
Project: `infinity-arcade-Jay`
Frontend canister: `mprew-viaaa-aaaah-quola-cai`
Backend canister: `pifyq-raaaa-aaaab-agrqq-cai` (not changed)
Implementation commit: `e813bc3e`

## Change

- Kept the parent-to-game keyboard bridge so shell-held keyboard focus can still forward Space to Swing Blade.
- Replaced the prior click-capturing focus overlay with a passive semi-transparent hint: `Click Game to activate keyboard`.
- The hint is `pointer-events:none` and cannot block `PLAY`, Insert Token, iframe clicks, or gameplay clicks.
- Swing Blade posts `arcade-input-ready` only after its canvas is confirmed as `document.activeElement`.
- Parent dismisses the hint only when the current `gameIframe.contentWindow` sends `arcade-input-ready`.

## Review

- First Gmai review: `docs/runbooks/infinity-arcade-swing-blade-passive-focus-hint-gmai-review-2026-05-14.md` => `REVISE REQUIRED` for overly loose ready-source dismissal.
- Rereview after fix: `docs/runbooks/infinity-arcade-swing-blade-passive-focus-hint-rereview-2026-05-14.md` => `APPROVE`.

## Predeploy Gates

Commands run from canonical root `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`:

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

- `validate-swing-blade-input-bridge`: PASS 36/36
- `node --check tmp\check-index.mjs`: PASS
- `node --check tmp\check-swing-blade.mjs`: PASS
- Sanitized publish payload built under `.deploy/frontend-public` with 35 files.
- Predeploy check passed for active frontend canister `mprew-viaaa-aaaah-quola-cai`.
- ICP deploy identity guard passed for `mcp-identity` / principal `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`.

## Deploy

Because both `/index.html` and `/games/swing-blade/index.html` changed, this was not index-only. Deployed the two changed frontend assets directly via asset canister `store`, each with `identity` and `gzip` encodings:

- `/index.html`
- `/games/swing-blade/index.html`

All four `store` calls returned `()`.

## Live Verification

Raw live asset SHA verification against local sanitized payload:

- `/index.html`
  - local/live SHA256: `d27831015f373a685f3b8f228ba1e926e27334ed153ba3b5159f4339e0886e16`
  - bytes: `1170519`
  - match: true
- `/games/swing-blade/index.html`
  - local/live SHA256: `fca7f7046a0a106d3d1dd2513eec961114449a0fb44761fb5d0ee1d147d2f2aa`
  - bytes: `203454`
  - match: true

## Residual Risk

- Browser gameplay smoke still recommended with Jay: start Swing Blade, click `PLAY`, then verify the hint does not block clicks and dissipates after the game receives focus.
- Backend/economics/session payment logic was not changed.
