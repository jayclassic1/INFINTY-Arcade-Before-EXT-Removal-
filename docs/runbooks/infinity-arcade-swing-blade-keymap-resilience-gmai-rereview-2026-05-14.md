# Gmai rereview: Swing Blade Space input keymap resilience

Task: `infinity-arcade-swing-blade-keymap-resilience-rereview-2026-05-14`
Project: `infinity-arcade-Jay`
Root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
Target frontend canister: `mprew-viaaa-aaaah-quola-cai`

## Scope / write guard

- Required dispatch fields were present: `PROJECT_ID`, `ROOT_PATH`, `ALLOWED_WRITE_ROOTS`, `TASK_ID`, `OUTPUT_LANE`, `EVIDENCE_DESTINATION`.
- `verify_write_scope` tool was not available in this session, so I used **manual path-containment fallback**.
- Planned write path resolved to `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks\infinity-arcade-swing-blade-keymap-resilience-gmai-rereview-2026-05-14.md`, which is under allowed root `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks`.
- Review only. No deploy performed.

## Verdict

Verdict: APPROVE

## Evidence checked

- `index.html`
  - `getKeyMap()` now catches malformed `localStorage` JSON, starts from `DEFAULT_KEY_MAP`, always returns normalized `p1`/`p2` maps, and only accepts non-empty string saved key codes.
  - `forwardArcadeKeyToGame()` tolerates missing player maps and tracks whether the exact native fallback `{player:'p1', action:'a'}` was already sent.
  - Space fallback now dispatches P1-A unless the exact P1-A mapping already fired, so unrelated custom mappings no longer suppress Swing Blade's native Space prompt path.
- `.deploy/frontend-public/index.html`
  - Same relevant `getKeyMap()` and Space fallback code is present in the deploy artifact.
  - SHA256 matches root `index.html`: `699f5db75b911bf71c6eb44b13c7e8bf8c1a51812e1d8c8de9d828d6a758fe54`.
- `scripts/validate-swing-blade-input-bridge.mjs`
  - Regression checks updated to require normalized parent keymap behavior and exact P1-A fallback suppression only.
- `scripts/validate-swing-blade-keymap-resilience.mjs`
  - New guard covers malformed JSON, default p1/p2 normalization, non-empty string acceptance, missing player map tolerance, exact Space fallback behavior, and P1-A fallback identity.
- `scripts/validate-frontend-deploy-artifact-sync.mjs`
  - New SHA guard compares root `index.html` to `.deploy/frontend-public/index.html`.
- `icp.yaml` / `deploy-manifest.json` / `README_CANONICAL_DEPLOY.md`
  - Active frontend deploy source is `.deploy/frontend-public` and active frontend canister is `mprew-viaaa-aaaah-quola-cai`.

## Tests / commands run

From `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`:

- `git status --short -- index.html .deploy/frontend-public/index.html scripts/validate-swing-blade-input-bridge.mjs scripts/validate-swing-blade-keymap-resilience.mjs scripts/validate-frontend-deploy-artifact-sync.mjs`
  - Confirmed modified root/deploy index and bridge validator; new keymap and deploy sync validators are untracked.
- `git diff --stat -- index.html .deploy/frontend-public/index.html scripts/validate-swing-blade-input-bridge.mjs scripts/validate-swing-blade-keymap-resilience.mjs scripts/validate-frontend-deploy-artifact-sync.mjs`
  - Relevant tracked changes: `.deploy/frontend-public/index.html`, `index.html`, `scripts/validate-swing-blade-input-bridge.mjs`.
- `node scripts\validate-frontend-deploy-artifact-sync.mjs`
  - PASS; root and deploy SHA both `699f5db75b911bf71c6eb44b13c7e8bf8c1a51812e1d8c8de9d828d6a758fe54`.
- `node scripts\validate-swing-blade-keymap-resilience.mjs`
  - PASS 6/6.
- `node scripts\validate-swing-blade-input-bridge.mjs`
  - PASS 41/41.
- `node scripts\validate-arcade-session-resume.mjs`
  - PASS 5/5.
- `node tmp\extract-html-scripts.cjs`
  - Extracted `index.html -> tmp/check-index.mjs` and `games/swing-blade/index.html -> tmp/check-swing-blade.mjs`.
- `node --check tmp\check-index.mjs`
  - PASS (syntax check exited 0).
- `node --check tmp\check-swing-blade.mjs`
  - PASS (syntax check exited 0).
- `node -e "const fs=require('fs'),crypto=require('crypto'); for(const f of ['index.html','.deploy/frontend-public/index.html']) console.log(f, crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex'));"`
  - Confirmed matching SHA256 for root and deploy artifact.

Note: an initial combined PowerShell command using `&&` failed before checks because this shell does not accept `&&` as a separator. It did not affect project files or the review result.

## Issues

- None blocking.

## Residual risk

- Static/script validation only; I did not deploy and did not perform a live canister/browser smoke test.
- The new validator scripts are currently untracked in git status and must be included with the patch before release.
- Existing unrelated workspace changes outside this patch are extensive; release staging should include only the scoped files.

## Safe for frontend deploy?

Yes — safe for a reviewed frontend deploy to active frontend canister `mprew-viaaa-aaaah-quola-cai`, provided the deploy uses the canonical `.deploy/frontend-public` / index-only path and stages only the scoped files. Do not deploy from project root or legacy paths.

## Next action

Ship/release through the normal frontend deploy path. No deploy was performed by Gmai.
