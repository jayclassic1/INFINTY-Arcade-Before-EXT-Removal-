# Gmai Review: Swing Blade dual-path Space/focus patch

Verdict: APPROVE

## Scope / write containment
- TASK_ID: infinity-arcade-swing-blade-dual-path-space-review-2026-05-14
- PROJECT_ID: infinity-arcade-Jay
- OUTPUT_LANE: task_evidence
- ROOT_PATH: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Evidence written to: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks\infinity-arcade-swing-blade-dual-path-space-gmai-review-2026-05-14.md`
- Scope tool unavailable; manual path-containment fallback performed. Planned/actual write path resolves under allowed root `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks`.

## Evidence checked
- Reviewed scoped diff for:
  - `index.html`
  - `.deploy/frontend-public/index.html`
  - `scripts/validate-swing-blade-input-bridge.mjs`
- Verified root/deploy artifact sync by SHA-256:
  - `index.html`: `361ec97ead6000b4e2a04bdec0f5ec9a52fdd8de780ac2b26268f52d2d96d868`
  - `.deploy/frontend-public/index.html`: `361ec97ead6000b4e2a04bdec0f5ec9a52fdd8de780ac2b26268f52d2d96d868`
- Diff scope is frontend focus/input bridge only: 3 files changed, 42 insertions / 20 deletions in reviewed scope.
- No backend, economy, payout, treasury, Candid, or canister logic changes found in the scoped patch; validator also confirms no added backend/canister call tokens in the Swing Blade input bridge patch.
- Focus behavior inspection:
  - `arcade-focus-request` now calls `ensureGameIframeFocus()` for the current iframe.
  - `arcade-game-interaction` dismisses passive hint and preserves iframe-native focus via `ensureGameIframeFocus()` instead of pulling focus back to `#m-backroom-game`.
  - Launch timers in `insertCoin()` and `tryGameDemo()` prefer iframe focus and do not call `dismissGameFocusOverlay()`.
  - Modal click handler prefers iframe focus and does not auto-dismiss the passive hint.
- Passive focus hint remains non-blocking:
  - Created as a `div` with `pointer-events:none`.
  - Uses approved copy: `Click Game to activate keyboard`.
  - Appears after 650ms only if still connected and not dismissed.
- Duplicate forwarding/text-entry inspection:
  - Capture-phase document `keydown`/`keyup` forwarding is present.
  - Existing window `keydown`/`keyup` forwarding remains as fallback.
  - `e.__arcadeForwardedToGame` guard prevents the same event from forwarding twice through capture + bubble/window paths.
  - Text-entry targets are protected via `target.isContentEditable` and `input`/`textarea`/`select` tag checks before forwarding/preventDefault.

## Tests run
- `node scripts\validate-frontend-deploy-artifact-sync.mjs` — PASS
- `node scripts\validate-arcade-session-resume.mjs` — PASS (5/5)
- `node scripts\validate-swing-blade-keymap-resilience.mjs` — PASS (6/6)
- `node scripts\validate-swing-blade-input-bridge.mjs` — PASS (43/43)
- `if(Test-Path tmp\extract-html-scripts.cjs){ node tmp\extract-html-scripts.cjs; node --check tmp\check-index.mjs; node --check tmp\check-swing-blade.mjs }` — PASS; extraction reported `index.html -> tmp/check-index.mjs (5 block(s))` and `games/swing-blade/index.html -> tmp/check-swing-blade.mjs (1 block(s))`; `node --check` produced no syntax errors.

## Issues
- None found in reviewed scope.

## Residual risk
- Static/validator coverage supports the dual-path focus strategy, but the original failure was observed in real Play flow; final confidence still benefits from an interactive browser playtest on the deployed/local frontend with Space after first game click.

## Next action
- Ship/re-test in real Play flow. If Space still fails, collect browser focus state (`document.activeElement`, iframe focusability, and posted `arcade-key` messages) during the failing interaction.
