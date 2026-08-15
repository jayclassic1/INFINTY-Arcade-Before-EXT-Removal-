# Phase 5 Production Deploy Evidence

Date: 2026-04-25 / 2026-04-26 UTC
Project: ICP-ARCADE / Infinity Arcade
Frontend canister: `mprew-viaaa-aaaah-quola-cai`
Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
Approved by: Jay Nolan in Discord #jaynolan (`approve deploy infinity arcade`)
Gmai deploy-readiness review: `tasks/gmai-arcade-phase5-final-deploy-readiness-review-20260425/review.md` = APPROVE

## Result

Backend upgraded successfully. Frontend was not mutated because the exact sanitized payload diff was already clean.

## Preflight

- System health: safe critical plugins, no open resilience circuits; overall degraded only by heartbeat/verification bookkeeping.
- ICP build env ready: `dfx 0.32.0`, `moc 1.4.1`, no missing tools.
- Authenticated principal: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`.
- Network: `ic` / `https://icp-api.io`.
- Gmai review verified before deploy.

## Frontend validation

Commands:

```powershell
node scripts\build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Result:

- Sanitized frontend payload generated at `.deploy/frontend-public`.
- Payload file count: 35.
- Predeploy check passed for `mprew-viaaa-aaaah-quola-cai` and exact sanitized source path.
- `icp_diff_assets` against `.deploy/frontend-public` returned:
  - `to_create: 0`
  - `to_update: 0`
  - `to_delete: 0`
  - `unchanged: 35`

Decision: no frontend asset deploy was performed because the live canister already matched the approved sanitized payload.

## Backend upgrade

Build:

```text
wasm_path=C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\backend\.build\arcade_backend\arcade_backend.wasm
wasm_size_bytes=739356
sha256=5a998b91dc913164e361c7acc9224ce44364fd4e25ac2f16be4dc94c244b1698
```

Dry run / preflight:

- `icp_upgrade_dryrun`: safe, non-noop, recommendation `SAFE to proceed`.
- `icp_preflight_check`: passed controller, cycles, and WASM checks.

Backup:

- Pre-upgrade snapshot ID: `000000000000000100000000002034610101`
- Snapshot size: `6180332`

Upgrade:

- First upgrade attempt without `wasm_memory_persistence` was rejected by the IC with `IC0504` because enhanced orthogonal persistence requires the upgrade option.
- Retried with `wasm_memory_persistence=keep`.
- Backend upgrade succeeded.

Post-upgrade backend status:

```text
status=running
module_hash=0x5a998b91dc913164e361c7acc9224ce44364fd4e25ac2f16be4dc94c244b1698
cycles≈3.086T
controllers include 7uj7m... and xcreu...
```

Post-upgrade smoke tests:

- `getRoyalties(7uj7m...)` query returned `0` successfully.
- `getRevenueSummary()` returned expected revenue rows successfully using tuple record decode.
- Frontend homepage `https://mprew-viaaa-aaaah-quola-cai.icp0.io/` returned HTTP 200 and visible `INFINITY ARCADE` content.

Release record:

- `backend/.releases/2026-04-26T01-29-28-200Z_pifyq-raaaa-aaaab-agrqq-cai.json`

## Residual notes

- Frontend remains at the approved sanitized payload; no asset mutation was necessary.
- The separate user request to remove `Gashapon Tickets` and `Mint NFT` from My Collection was not included in this deploy. That implementation dispatch failed without changes and needs a clean retry/recovery before review and any later frontend deploy.
