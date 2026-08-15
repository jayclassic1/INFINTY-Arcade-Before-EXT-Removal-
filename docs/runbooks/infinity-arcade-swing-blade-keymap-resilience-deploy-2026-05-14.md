# Infinity Arcade Swing Blade Keymap Resilience Deploy - 2026-05-14

## Scope

Frontend-only `/index.html` deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai`.

## Change

- Hardened `getKeyMap()` so malformed or partial `localStorage.arcade_keymap` data falls back to normalized defaults.
- Hardened `forwardArcadeKeyToGame()` so `Space` still reaches Swing Blade as P1-A unless the exact P1-A arcade action was already sent.
- Synced `.deploy/frontend-public/index.html` with reviewed root `index.html`.
- Added deploy-artifact SHA guard: `scripts/validate-frontend-deploy-artifact-sync.mjs`.

## Review

Gmai rereview: `APPROVE`

Artifact: `docs/runbooks/infinity-arcade-swing-blade-keymap-resilience-gmai-rereview-2026-05-14.md`

## Predeploy Gates

Passed:

- `node scripts\validate-frontend-deploy-artifact-sync.mjs`
- `node scripts\validate-swing-blade-keymap-resilience.mjs`
- `node scripts\validate-swing-blade-input-bridge.mjs`
- `node scripts\validate-arcade-session-resume.mjs`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Check -ExpectedCanister mprew-viaaa-aaaah-quola-cai`

Predeploy guard verified:

- Canonical root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Deploy source: `.deploy/frontend-public`
- Identity: `mcp-identity -> 7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`
- Controller on frontend/backend canisters verified by deploy guard.

## Deploy Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

## Deploy Result

Success. Stored both identity and gzip encodings for `/index.html`.

Live `/index.html` SHA256:

`699f5db75b911bf71c6eb44b13c7e8bf8c1a51812e1d8c8de9d828d6a758fe54`

Expected deploy artifact SHA256:

`699f5db75b911bf71c6eb44b13c7e8bf8c1a51812e1d8c8de9d828d6a758fe54`

## Postdeploy Verification

Passed:

- Fetched live raw `/index.html` with identity encoding and verified SHA256 matches expected deploy artifact.
- Live source contains defensive `getKeyMap()` parse fallback.
- Live source contains `nativeFallbackAlreadySent` Space fallback guard.
- Browser smoke: malformed `arcade_keymap` JSON + parent shell Space dispatch changed Swing Blade state from `title` to `playing`.
- Browser smoke: custom keymap with `Space` mapped to unrelated P1-B still changed Swing Blade state from `title` to `playing` via native Space fallback.

## Residual Risk

Browser smoke used synthetic key events rather than Jay's physical keyboard. Jay should hard-refresh and test the actual Play flow live.

## User Approval

Jay approved deployment in Discord before execution.
