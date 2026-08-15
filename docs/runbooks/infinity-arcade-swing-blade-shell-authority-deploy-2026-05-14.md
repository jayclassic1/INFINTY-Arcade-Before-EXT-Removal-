# Infinity Arcade Swing Blade Shell Authority Deploy — 2026-05-14

## Scope

Frontend-only deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai`.

No backend, economy, payout, treasury, Candid, or canister-state changes.

## Change

Patch commit: `47925cf3` — `Restore Swing Blade shell keyboard authority`

Summary:
- Makes the arcade shell the keyboard authority for Swing Blade / iframe games.
- `arcade-focus-request` and `arcade-game-interaction` restore focus to `#m-backroom-game` via `ensureGameShellKeyboardFocus()`.
- First game click/touch still unlocks audio and dismisses the passive hint, then returns keyboard authority to the shell so Space routes through the universal parent bridge.
- Play/demo launch timers focus the shell at 300ms and 900ms.
- Keeps the newer capture-phase document forwarding, window fallback forwarding, duplicate-event guard, text-entry guard, keymap normalization, and Space -> P1-A fallback.

## Review

Gmai review: `docs/runbooks/infinity-arcade-swing-blade-shell-authority-gmai-review-2026-05-14.md`

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

`6d2e5f1ba2943a6ec8a4ad79a9a15ebacd1697dd88f44d727d36408dbbb44012`

Post-deploy fetch verification:

- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html`
  - SHA256: `6d2e5f1ba2943a6ec8a4ad79a9a15ebacd1697dd88f44d727d36408dbbb44012`
  - contains shell-authority patch: yes
  - contains capture-phase bridge patch: yes
- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/games/swing-blade/index.html`
  - SHA256: `e44d7bace4173f1bfc17f09966c60c688b0ddbdbc671825f93b25d9d5df73d66`
  - contains `__swingBladeApplyArcadeKey`: yes

## Browser Smoke

Live synthetic same-origin smoke at:

`https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html?audit=shell-authority-live`

Injected same-origin Swing Blade iframe, focused parent modal shell, and pressed Space:

- Before Space: parent active element `m-backroom-game`, child state `title`.
- After Space: parent active element `m-backroom-game`, child state `playing`.

This specifically verifies the parent-shell keyboard bridge path that Jay's background-click test proved reliable.

## Rollback

Frontend rollback restore points:

- Last pre-Space-button work: `2210f2b8`.
- Current deploy patch: `47925cf3`.
- Prior dual-path iframe-focus deploy: `2544d7f4`, superseded by this shell-authority patch.

Because this was frontend asset code only, git restore/redeploy of a prior `/index.html` is the practical rollback path. Backend snapshots were not involved.

## Residual Risk

The failing case was Jay's physical browser Play flow. This deploy matches Jay's observed reliable path by forcing keyboard authority back to the shell. Jay should retest live Space after Play and after clicking inside the game/music start.
