# Infinity Arcade Swing Blade Dual-Path Space Deploy — 2026-05-14

## Scope

Frontend-only deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai`.

No backend, economy, payout, treasury, Candid, or canister-state changes.

## Change

Patch commit: `2544d7f4` — `Fix Swing Blade dual path keyboard focus`

Summary:
- Preserve iframe/native keyboard focus after Swing Blade focus requests and first game interaction.
- Stop pulling focus back to `#m-backroom-game` after game click/touch.
- Keep parent arcade keyboard bridge as fallback using capture-phase document listeners plus existing window listeners.
- Add duplicate-event guard `e.__arcadeForwardedToGame`.
- Avoid intercepting text-entry targets.
- Keep passive focus hint non-blocking and synced deploy artifact.

## Review

Gmai review: `docs/runbooks/infinity-arcade-swing-blade-dual-path-space-gmai-review-2026-05-14.md`

Verdict: `APPROVE`

## Predeploy Gates

Passed before deploy:

- `node scripts\validate-frontend-deploy-artifact-sync.mjs`
- `node scripts\validate-arcade-session-resume.mjs`
- `node scripts\validate-swing-blade-keymap-resilience.mjs`
- `node scripts\validate-swing-blade-input-bridge.mjs`
- `node tmp\extract-html-scripts.cjs`
- `node --check tmp\check-index.mjs`
- `node --check tmp\check-swing-blade.mjs`

Deploy script gates:

- Canonical root guard passed.
- Active frontend canister guard passed: `mprew-viaaa-aaaah-quola-cai`.
- Frontend payload built to `.deploy/frontend-public`.
- Predeploy check passed for `.deploy/frontend-public`.
- `npm run deploy:guard` passed:
  - identity: `mcp-identity`
  - principal: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`
  - controller on backend and frontend canisters verified.

## Deploy Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

## Deploy Result

Stored both encodings for `/index.html`:

- identity: success `()`
- gzip: success `()`

Live raw `/index.html` identity SHA verified by deploy script:

`361ec97ead6000b4e2a04bdec0f5ec9a52fdd8de780ac2b26268f52d2d96d868`

Post-deploy fetch verification:

- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html`
  - SHA256: `361ec97ead6000b4e2a04bdec0f5ec9a52fdd8de780ac2b26268f52d2d96d868`
  - contains `ensureGameIframeFocus()` patch: yes
- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/games/swing-blade/index.html`
  - SHA256: `e44d7bace4173f1bfc17f09966c60c688b0ddbdbc671825f93b25d9d5df73d66`
  - contains `__swingBladeApplyArcadeKey`: yes

## Browser Smoke

Live synthetic iframe smoke at:

`https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html?audit=dual-path-live`

Injected same-origin Swing Blade iframe and pressed Space:

- Before Space: child state `title`, parent active element `gameIframe`, child active element `gameCanvas`.
- After Space: child state `playing`, parent active element `gameIframe`, child active element `gameCanvas`.

## Rollback

Frontend rollback restore points:

- Last pre-Space-button work: `2210f2b8`.
- Space/focus steps after that: `e813bc3e`, `362cf5e4`, `92900a02`, `b5675ccf`, `8f54517d`, `2544d7f4`.

Because this was frontend asset code only, git restore/redeploy of a prior `/index.html` is the practical rollback path. Backend snapshots were not involved.

## Residual Risk

The failing case was Jay's physical browser Play flow. Synthetic smoke now passes with iframe focus preserved, but Jay should retest live Spacebar in the normal Play flow.
