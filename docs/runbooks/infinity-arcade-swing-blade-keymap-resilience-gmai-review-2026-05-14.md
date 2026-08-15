# Gmai Review: Swing Blade keymap resilience

Verdict: REVISE REQUIRED

Evidence checked:
- Manual path-containment fallback completed before tests/writes: planned artifact path `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks\infinity-arcade-swing-blade-keymap-resilience-gmai-review-2026-05-14.md` resolves under allowed root `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks\`.
- `git diff -- index.html scripts/validate-swing-blade-input-bridge.mjs scripts/validate-swing-blade-keymap-resilience.mjs`
- `scripts/validate-swing-blade-keymap-resilience.mjs`
- `scripts/validate-swing-blade-input-bridge.mjs`
- `icp.yaml`
- `.deploy/frontend-public/index.html` targeted inspection

Tests run:
- `node scripts\validate-swing-blade-keymap-resilience.mjs` => PASS 6/6
- `node scripts\validate-swing-blade-input-bridge.mjs` => PASS 41/41
- `node scripts\validate-arcade-session-resume.mjs` => PASS 5/5
- `node tmp\extract-html-scripts.cjs` => extracted `index.html` and `games/swing-blade/index.html` scripts
- `node --check tmp\check-index.mjs` => PASS / no syntax errors
- `node --check tmp\check-swing-blade.mjs` => PASS / no syntax errors

Issues:
1. CRITICAL: Not safe for frontend deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai` yet. `icp.yaml` configures the frontend asset canister source as `.deploy/frontend-public`, but `.deploy/frontend-public/index.html` is stale relative to the reviewed root `index.html` patch.
   - `.deploy/frontend-public/index.html:5201` still has the old unsafe `function getKeyMap(){return JSON.parse(localStorage.getItem('arcade_keymap')||JSON.stringify(DEFAULT_KEY_MAP));}`.
   - `.deploy/frontend-public/index.html:6734` still has `if(fallback&&!forwarded)`, so Space fallback is still suppressed when Space is mapped to any unrelated action.
   - Therefore a configured frontend deploy would not ship the keymap-resilience fix currently present in root `index.html`.

Residual risk:
- Root `index.html` logic and validators are internally consistent and tests pass, but deploy artifact drift means the live canister deployment path can omit the fix.
- Existing validators read root `index.html`; they do not protect against `.deploy/frontend-public/index.html` drift.

Next action:
- Revise by regenerating/copying the patched root `index.html` into `.deploy/frontend-public/index.html` or changing the deploy process to build from the reviewed source, then rerun the validators against the actual configured deploy asset directory before requesting Gmai approval.
- Do not deploy until the configured deploy artifact contains the same keymap resilience changes.
