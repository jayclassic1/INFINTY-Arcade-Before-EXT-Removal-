# Infinity Arcade Mainnet Baseline Before Ticket Payout Work — 2026-04-27

## Purpose
Record the deployed state after the ICP CLI / WSL migration, Token buying hotfix, and frontend soft-audit sanitizer sync, before starting the next ticket payout calibration work.

## Canonical Project
- Root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Live frontend: `https://mprew-viaaa-aaaah-quola-cai.icp0.io/`
- Deploy identity: `mcp-identity`
- Deploy principal: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`

## Current Live State
### Backend
- Status: Running
- Module hash: `0x8fa74bbe3edf645b8fc6e3e17e89bb88a535560520da38bd5fe98af82abb0bb2`
- Controllers: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`, `xcreu-r77dk-scpjr-fua34-suphw-f44ha-gpmwm-i2ncz-hm6uo-zn6f3-xae`
- Cycles at baseline check: `3_016_772_588_951`

### Frontend
- Status: Running
- Module hash: `0x763ae81b8e134067a1d622e1f2c561d60a0a538b5cc95cad804097f8ea6fa8c0`
- Controllers: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`, `xcreu-r77dk-scpjr-fua34-suphw-f44ha-gpmwm-i2ncz-hm6uo-zn6f3-xae`
- Cycles at baseline check: `2_240_237_129_186`
- Live page title: `Infinity Arcade`

## Verified Frontend Sanitizer State
Remote HTML checks after frontend sync:
- `safeUserErrorMessage`: YES
- Badge purchase path sanitized: YES
- DAO/forum reply path sanitized: YES
- Raw global `JS ERROR` / `PROMISE ERROR` banners removed: YES

## Ticket Pool Baseline
Swing Blade game:
- Game ID: `game-1-1777223039629610695`
- Raw ticket pool: `14`
- Backed/payable ticket pool: `14`

Interpretation: Jay's two Token plays funded the Swing Blade ticket pool at 7 backed tickets per Token.

## Completed Deploy Work Captured By This Baseline
- ICP CLI / WSL deployment path active; no DFX active build path.
- `backend/dfx.json` remains legacy reference only.
- `scripts/run-icp-tool.mjs` routes allowed ICP tools through WSL.
- `scripts/guard-no-dfx-active-build.mjs` blocks active DFX usage.
- `scripts/guard-icp-deploy-identity.mjs` blocks anonymous/plaintext/wrong-controller deploys.
- `convertDepositToTokens` is deployed on backend and moves verified ICP from caller deposit subaccount to backend main account before crediting internal Tokens.
- Legacy `deposit(_icpE8s, _blockIndex)` is disabled.
- `withdrawDeposit*` requires caller-owned subaccount matching.
- Frontend soft-audit sanitizer patch is live.

## Rollback / Snapshot References
- Initial deploy snapshot: `000000000000000600000000002034610101`
- Hotfix deploy snapshot: `000000000000000700000000002034610101`

## Pre-Next-Deploy Notes
- Next workstream: ticket payout calibration / solvency model.
- Do not deploy ticket payout changes without fresh build, Gmai review, identity guard, predeploy check, explicit live approval, and a new backend snapshot if backend upgrade is required.
- Current ticket payout code still has the trial/no-ticket behavior; this baseline intentionally records the state before changing it.
