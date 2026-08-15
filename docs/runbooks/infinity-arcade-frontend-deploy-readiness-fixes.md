# Infinity Arcade frontend deploy readiness fixes

Task: `icp-arcade-frontend-deploy-readiness-fixes-20260614`  
Project: ICP-ARCADE  
Target frontend canister: `mprew-viaaa-aaaah-quola-cai`  
Backend target context: `pifyq-raaaa-aaaab-agrqq-cai` (not changed/deployed)  
Trace: `f9be72bfc99b4f63999f4b357caf5fb0`

## Scope

Readiness-only frontend/source patch. No live ICP mutation, no raw DFX, no deploy/install/upgrade/upload, and no controller/cycles/identity changes.

## Changes

- Kept treasury withdrawal actions disabled unless the backend exposes both balance read and required payout/sweep methods.
- Updated treasury copy to label the backend-derived cap as safe withdrawable surplus.
- Displayed returned jackpot tier/source labels in jackpot popup detail while preserving existing total-ticket popup copy.
- Synchronized reviewed `index.html` into `.deploy/frontend-public/index.html` for sanitized frontend deploy payload readiness.

## Verification

All commands were run from `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`.

| Command | Result |
| --- | --- |
| `node scripts\validate-treasury-safety-gate-phase1.mjs` | PASS (10/10) |
| `node scripts\test-ticket-jackpot-tiers-phase2-payouts.mjs` | PASS |
| `node scripts\test-ticket-jackpot-tiers-phase3-frontend-history.mjs` | PASS |
| `node scripts\validate-frontend-deploy-artifact-sync.mjs` | PASS; root/deploy sha256 `8a01a0e487a78cb90a7c150e81dcd3f37025a5ddde9e7edeb7b3f30da97950cb` |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai` | PASS; verified frontend canister and sanitized payload source; 36 files |
| `git --no-pager diff --check -- index.html .deploy/frontend-public/index.html` | PASS |

## Notes

- The `.deploy/frontend-public/index.html` sync includes current reviewed root `index.html` content so the deploy artifact sync validator is green.
- No backend files were edited for this task.
- No live deployment was performed.
