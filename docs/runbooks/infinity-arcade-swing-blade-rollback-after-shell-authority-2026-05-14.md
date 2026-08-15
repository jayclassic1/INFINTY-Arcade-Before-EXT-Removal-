# Infinity Arcade Swing Blade Rollback After Shell Authority Regression — 2026-05-14

## Reason

Jay reported that after shell-authority deploy `6d2e5f1ba2943a6ec8a4ad79a9a15ebacd1697dd88f44d727d36408dbbb44012`, none of the three Space paths worked:

1. after hitting Play,
2. after clicking inside the game/music start,
3. after clicking parent background.

This was worse than the prior dual-path deploy, where Jay reported the parent background click path worked.

## Rollback Target

Restored frontend source from commit `2544d7f4` (`Fix Swing Blade dual path keyboard focus`) and deployed index-only to active frontend canister `mprew-viaaa-aaaah-quola-cai`.

This restores the previous live behavior before the shell-authority regression.

## Commands

```powershell
git restore --source=2544d7f4 -- index.html
Copy-Item -Path index.html -Destination .deploy\frontend-public\index.html -Force
node scripts\validate-frontend-deploy-artifact-sync.mjs
node tmp\extract-html-scripts.cjs
node --check tmp\check-index.mjs
node --check tmp\check-swing-blade.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

## Verification

Predeploy checks:

- deploy artifact sync PASS
- HTML script extraction PASS (`index.html -> tmp/check-index.mjs (5 block(s))`)
- `node --check tmp\check-index.mjs` PASS
- `node --check tmp\check-swing-blade.mjs` PASS
- predeploy canister/source guard PASS
- deploy identity guard PASS

Deploy result:

- identity store: `()`
- gzip store: `()`
- live raw `/index.html` verified by deploy script

Live SHA after rollback:

`3b908e34473591cf51ef06bcc7db5f762b6bdcda960d793de43af67b13980b2b`

Postdeploy fetch verification:

- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html`
  - SHA256: `3b908e34473591cf51ef06bcc7db5f762b6bdcda960d793de43af67b13980b2b`
  - contains dual-path iframe focus patch: yes
  - contains capture-phase bridge patch: yes
- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/games/swing-blade/index.html`
  - SHA256: `e44d7bace4173f1bfc17f09966c60c688b0ddbdbc671825f93b25d9d5df73d66`
  - contains `__swingBladeApplyArcadeKey`: yes

## Notes

PowerShell redirection was initially attempted with `git show ... > index.html`, which produced a bad text encoding and an extraction result of 0 script blocks. This was immediately corrected with `git restore --source=2544d7f4 -- index.html` before deploy.

## Next Diagnostic Hypothesis

The shell-authority strategy failed in production physical testing, so the next fix should not be another focus-only guess.

Next step should add a minimal visible/internal diagnostic layer or debug route to prove exactly where physical Space dies:

- parent `keydown` capture listener fired?
- parent `forwardArcadeKeyToGame` returned true?
- iframe `postMessage({type:'arcade-key'})` sent?
- game iframe message listener received `arcade-key`?
- `InputManager.applyArcadeAction('a','down')` ran?
- `game.input.justPressed.Space` set before title/play frame?

Then patch the confirmed failing segment.
