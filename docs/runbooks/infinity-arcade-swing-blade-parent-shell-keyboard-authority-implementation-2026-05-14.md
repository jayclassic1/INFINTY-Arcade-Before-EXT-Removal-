# Infinity Arcade Swing Blade Parent Shell Keyboard Authority Implementation - 2026-05-14

Task ID: `infinity-arcade-swing-blade-parent-shell-keyboard-authority-2026-05-14`
Project: `infinity-arcade-Jay`

## Issue

Jay reported this sequence:

1. Click game card and hit Play.
2. Space works immediately.
3. Click inside Swing Blade; menu music starts.
4. Space stops working.
5. Click outside/behind the gameplay popup.
6. Space works again.

## Root Cause

The known-good path is parent shell keyboard capture plus the parent-to-game `arcade-key` bridge. Clicking inside the child iframe can unlock audio while moving browser focus away from the parent shell, but without giving Swing Blade reliable native key focus. That creates a dead zone until a click outside the iframe refocuses the parent shell.

## Change

- Added `ensureGameShellKeyboardFocus()` in `index.html`.
- Current-iframe `arcade-focus-request` now focuses the parent game modal shell, not the iframe.
- Current-iframe first `arcade-game-interaction` still dismisses the hint, then focuses the parent shell.
- Session launch timers now focus the parent shell at 300ms and 900ms.
- Parent modal click refocuses the parent shell.
- Kept the child click/touch behavior that starts audio, requests focus, attempts canvas focus, and reports first interaction.
- Kept parent Space/action forwarding and Swing Blade `applyArcadeAction` bridge unchanged.

## Files Changed

- `index.html`
- `scripts/validate-swing-blade-input-bridge.mjs`
- This runbook

## Tests

Commands run:

```powershell
node scripts\validate-swing-blade-input-bridge.mjs
node tmp\extract-html-scripts.cjs
node --check tmp\check-index.mjs
node --check tmp\check-swing-blade.mjs
```

Results:

- Validator: PASS 40/40
- Script extraction: PASS
- Index syntax check: PASS
- Swing Blade syntax check: PASS

## Scope

Frontend-only. No backend, canister, payment, scoring, ticket economy, or session accounting logic changed.

## Residual Risk

Browser iframe focus behavior can vary. The fix intentionally makes the parent shell the keyboard authority during active gameplay because that is the path Jay confirmed works.
