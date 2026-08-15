# Infinity Arcade Ticket Jackpot Live Deploy — 2026-05-13

## Scope

Deployed reviewed ticket jackpot Phase 1 plus admin jackpot threshold UI/config to active production canisters only.

- Backend: `pifyq-raaaa-aaaab-agrqq-cai`
- Frontend: `mprew-viaaa-aaaah-quola-cai`
- Git commit deployed: `d692f1e583ea3d0f6789ce7d0ba1cd5ba9ee69fb`
- No legacy canisters targeted.

## Approval

Jay approved deploy in `#jaynolan` on 2026-05-13 after explicit deploy summary.
Jay also approved deletion of the oldest backend snapshot after the canister reported the 10-snapshot limit.

## Preflight

- `node scripts\guard-icp-deploy-identity.mjs` — PASS
  - identity: `mcp-identity`
  - principal: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`
  - controller on backend and frontend confirmed
- `npm run predeploy:check` — PASS
  - backend build passed
  - frontend deploy source confirmed: `.deploy\frontend-public`
  - sanitized payload files: 35

## Snapshot Gate

Backend snapshot creation initially failed because `pifyq-raaaa-aaaab-agrqq-cai` had the max 10 snapshots.

Deleted oldest snapshot after approval:
- `000000000000000a00000000002034610101`

Created fresh pre-upgrade snapshot:
- `000000000000001400000000002034610101`
- size: `11719496` bytes

## Backend Upgrade

Installed local WASM via `icp canister install ... --mode upgrade`.

- Local WASM SHA256: `7224a5ac8febe4c2866afc950cb19389cb2312aad7246b812fc8b60b42080506`
- Post-upgrade module hash: `0x7224a5ac8febe4c2866afc950cb19389cb2312aad7246b812fc8b60b42080506`
- Backend status: Running

## Frontend Deploy

Used hardened index-only deploy path for the active frontend canister.

- Live `/index.html` SHA256: `e5c217477d526e7e3fc9f5284770340c4d31834ef7361aac9c80cf9b6b235f24`
- Local expected `/index.html` SHA256: `e5c217477d526e7e3fc9f5284770340c4d31834ef7361aac9c80cf9b6b235f24`
- Live SHA verified equal.

## Postdeploy Verification

Backend calls:
- `getRecentTicketJackpotWins(5)` — returned `(vec {})`
- `getAllGameTicketJackpotConfigs()` — returned `(vec {})`
- Backend status — Running

Live frontend raw index contains:
- `Ticket Jackpot Threshold` — true
- `setGameTicketJackpotConfig` — true
- `jackpotTickets` — true

## Result

Deploy completed successfully. Ticket jackpots and admin-configurable jackpot score thresholds are live on the active Infinity Arcade canisters.
