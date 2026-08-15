# Canonical mprew Validation — 2026-04-25

## Scope
Validate that the canonical Infinity Arcade root `dapps/infinity-arcade-Jay` now deploys cleanly to the new frontend asset canister and talks to the fresh backend canister.

## Active Canister Map

- Frontend asset canister: `mprew-viaaa-aaaah-quola-cai`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Legacy frontend fallback: `ewgfh-vqaaa-aaaah-qtixa-cai`

## Preflight

- ICP identity authenticated as `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`.
- ICP network: `ic` / `https://icp-api.io`.
- Frontend canister status before deploy: running, ~3.064T cycles.
- Backend canister status before deploy: running, ~3.112T cycles.

## Package Build

Built canonical clean frontend package from:

`C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`

Package path:

`C:\Users\Jesse\.openclaw\workspaces\jmai\tmp\infinity-arcade-canonical-frontend-mprew`

Package results:

- File count: 35
- `x47vc-qaaaa-aaaai-radva-cai`: absent
- `sympv-naaaa-aaaad-qktuq-cai`: absent
- `ewgfh-vqaaa-aaaah-qtixa-cai`: absent
- `pifyq-raaaa-aaaab-agrqq-cai`: present in active runtime constants

Runtime constants in packaged `index.html`:

- `ARCADE_CANISTER_ID='pifyq-raaaa-aaaab-agrqq-cai'`
- `TREASURY_PRINCIPAL='pifyq-raaaa-aaaab-agrqq-cai'`
- `BACKEND_CANISTER='pifyq-raaaa-aaaab-agrqq-cai'`
- `VAULT_PRINCIPAL='pifyq-raaaa-aaaab-agrqq-cai'`

## Deploy

- Deployed package to `mprew-viaaa-aaaah-quola-cai`.
- Upload result: 35/35 files uploaded, 35 updated, 0 failed.
- Uploaded `/games/skate-apocalypse/` direct route alias from Shred Gnar `index.html`.
- Final frontend asset count: 36.

## Frontend Verification

Live URL:

`https://mprew-viaaa-aaaah-quola-cai.icp0.io`

Checks:

- Homepage HTTP status: 200
- Homepage contains `pifyq-raaaa-aaaab-agrqq-cai`: true
- Homepage contains `x47vc-qaaaa-aaaai-radva-cai`: false
- Homepage contains `sympv-naaaa-aaaad-qktuq-cai`: false
- Homepage contains `ewgfh-vqaaa-aaaah-qtixa-cai`: false
- Manifesto HTTP status: 200
- Shred Gnar route title: `Shred Gnar | Infinity Arcade`

## Backend Verification

Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`

Query smoke checks passed:

- `getTotalRevenue`
- `getNftListings`
- `getGameSubmissions`
- `getAllNftCosts`

## Result

PASS. Canonical root now redeploys to the new `mprew` frontend and the live frontend points at the fresh `pifyq` backend. Old IDs are absent from the active served homepage/runtime path.

## Remaining Review Gate

A Gmai review should confirm the registry/docs/runtime alignment and identify any remaining stale legacy references that are harmless historical notes versus active deploy risk.

## Follow-up: Predeploy Guard Fix

Gmai review found `scripts/predeploy-check.ps1` still read the legacy `productionCanister` field while `deploy-manifest.json` now uses `frontendCanister`. The guard now:

- Prefers `frontendCanister` and verifies it equals `mprew-viaaa-aaaah-quola-cai`.
- Uses `productionCanister` only as a legacy fallback when `frontendCanister` is absent or blank.
- Fails closed when neither `frontendCanister` nor `productionCanister` is present.
- Verifies the canonical root is inside a git worktree with `git -C <root> rev-parse --is-inside-work-tree` instead of requiring a nested `.git` directory.

Local guard test output:

```text
TEST active manifest:
Predeploy check passed. Verified frontendCanister=mprew-viaaa-aaaah-quola-cai.
TEST legacy productionCanister fallback:
Predeploy check passed. Verified productionCanister=mprew-viaaa-aaaah-quola-cai.
TEST fail closed without frontendCanister/productionCanister:
Canister mismatch: deploy-manifest.json must define frontendCanister (preferred) or productionCanister (legacy fallback)
Missing canister field correctly failed closed.
```

Focused old-ID search across active frontend/deploy guard files (`index.html`, `dfinity-bundle.js`, `games`, `scripts/predeploy-check.ps1`):

```text
x47vc-qaaaa-aaaai-radva-cai: no matches
sympv-naaaa-aaaad-qktuq-cai: no matches
```
