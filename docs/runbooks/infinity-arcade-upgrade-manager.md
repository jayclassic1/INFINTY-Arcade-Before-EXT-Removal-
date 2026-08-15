# Infinity Arcade Upgrade Manager Runbook

This runbook describes the project-local, readiness-only bridge for future Infinity Arcade backend upgrades.

## Scope

- Project: `ICP-ARCADE`
- Project root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Generic lane provider mapping: `GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER`
- Mutation allowed now: `false`

The manager only creates a reusable approval/readiness packet. It does not deploy, upgrade, upload frontend assets, create canisters, touch controllers/cycles/identity/secrets, restart the gateway, or run raw local-network commands.

## Script

Primary manager:

```powershell
node scripts/prepare-infinity-arcade-upgrade.mjs --artifactDir=C:\Users\Jesse\OpenClawEvidence\icp-arcade-icp-tipping
```

Compatibility wrapper retained for older references:

```powershell
node scripts/prepare-jay-backend-upgrade-lane.mjs --artifactDir=C:\Users\Jesse\OpenClawEvidence\icp-arcade-icp-tipping
```

Both routes read fresh backend build artifacts only from:

- `backend/.build/arcade_backend.wasm`
- `backend/.build/arcade_backend.did`

Stale generated artifacts under `backend/.dfx/...` are intentionally not used.

## Required pre-step

Run the safe project wrapper build before generating a packet:

```powershell
npm run backend:build
```

Then generate the packet. The script recomputes SHA-256 hashes from `.build` every time.

## Fail-closed gates

The packet is blocked unless all of these pass:

1. `.build` WASM exists.
2. `.build` DID exists.
3. The oldest `.build` artifact timestamp is newer than or equal to the latest relevant backend source timestamp.
4. The `.build` DID contains:
   - `recordIcpTip`
   - `getGameIcpTipSummary`
   - `getRecentGameIcpTips`
5. `.releases/latest.json` exists and binds the backend canister to a 64-hex current module hash (`wasm_hash`), rollback module hash (`previous_hash`), upgrade mode, and source commit.
6. No CLI option implies live execution, frontend upload, new canister, full-stack deploy, controller/cycles/identity/secret access, raw local-network command, gateway restart, deploy, install, or upgrade.

The packet reports latest source and oldest artifact timestamps plus production provenance/rollback metadata in JSON and Markdown. The release manifest is project-local provenance only; governed live-state proof must still confirm the live canister module hash before mutation.

## Packet contents

Generated artifacts:

- `infinity-arcade-upgrade-readiness.json`
- `infinity-arcade-upgrade-readiness.md`

The packet includes:

- schema/lane id
- mapping to `GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER`
- project id/root
- backend/frontend canister ids
- candidate WASM/DID paths and SHA-256 hashes
- required backend methods present/missing
- freshness timestamps
- production provenance from `.releases/latest.json`
- current deployed module hash expected by the local release manifest
- rollback bundle hash/source commit metadata
- stable migration/test checklist
- pre-upgrade state proof requirements
- rollback placeholders
- post-verify placeholders
- `mutationAllowedNow: false`
- governed safe-wrapper proof requirement

## Regression tests

Run:

```powershell
node scripts/test-infinity-arcade-upgrade-manager.mjs
node scripts/test-jay-backend-upgrade-lane.mjs
node scripts/test-icp-tip-ui-contract.mjs
```

Coverage includes:

- `.dfx` artifacts are not used
- `.build` DID methods are recognized
- missing required DID methods block readiness
- stale `.build` artifacts block readiness
- live/execute/mutation flags fail closed
- generic lane mapping is present while `mutationAllowedNow` remains `false`

## Future live execution requirements

Before any live backend upgrade, a separate governed safe-wrapper proof is still required for `GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER`. A future execution packet must also include pre-upgrade state proof, reviewed candidate hashes, rollback proof/placeholders filled in, and post-upgrade verification steps. This runbook and manager are not authorization to execute a live mutation.
