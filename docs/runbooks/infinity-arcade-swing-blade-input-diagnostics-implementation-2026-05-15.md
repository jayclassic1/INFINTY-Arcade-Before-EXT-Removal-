# Infinity Arcade Swing Blade Input Diagnostics Implementation - 2026-05-15

## Scope

Temporary diagnostic instrumentation only. No backend, payout, token, or economics behavior changed.

## Changed files

- `index.html`
- `.deploy/frontend-public/index.html`
- `games/swing-blade/index.html`
- `.deploy/frontend-public/games/swing-blade/index.html`
- `scripts/validate-swing-blade-input-bridge.mjs`

## Diagnostic route

Enable by opening the arcade with either:

- `?inputDebug=1`
- or `localStorage.setItem('arcade_input_debug','1')`

When enabled, the parent page shows a passive bottom-left debug panel and logs `[ArcadeInputDebug]` entries in the console.

## Instrumented path

The diagnostics trace the real physical Space path:

1. parent keydown/keyup capture listener
2. `forwardArcadeKeyToGame(e,state)` gate/skip reason
3. parent `postMessage({ type: 'arcade-key' })`
4. Swing Blade iframe receives `arcade-key`
5. `window.__swingBladeApplyArcadeKey`
6. `InputManager.applyArcadeAction`
7. `Space` `justPressed`
8. title screen consuming Space and starting gameplay

## Verification

Passed from `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`:

- `node scripts\validate-frontend-deploy-artifact-sync.mjs`
- `node scripts\validate-arcade-session-resume.mjs`
- `node scripts\validate-swing-blade-keymap-resilience.mjs`
- `node scripts\validate-swing-blade-input-bridge.mjs`
- `node tmp\extract-html-scripts.cjs`
- `node --check tmp\check-index.mjs`
- `node --check tmp\check-swing-blade.mjs`
- `git diff --check -- index.html games/swing-blade/index.html .deploy/frontend-public/index.html .deploy/frontend-public/games/swing-blade/index.html scripts/validate-swing-blade-input-bridge.mjs`

## Deploy gate

Not deployed. Requires Gmai approval and explicit user deploy authorization.
