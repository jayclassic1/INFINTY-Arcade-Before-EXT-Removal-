# Infinity Arcade Universal Start Overlay Deploy - 2026-05-20

## Scope

Frontend-only deploy for the universal Showroom Start overlay.

- Project: ICP-ARCADE / Infinity Arcade
- Canonical root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai` (not changed)
- Reviewed commit: `564c27a59985e03ced3ef8a39ef1c634514e7095`
- Deploy type: index-only frontend asset update

## Review Gate

Gmai review passed and verifier accepted the review artifact.

- Review artifact: `C:\Users\Jesse\OpenClawEvidence\ICP-ARCADE-UNIVERSAL-START-OVERLAY-GMAI-2026-05-20\review.md`
- Verified proof line: `REVIEW_VERDICT: PASS path=C:\Users\Jesse\OpenClawEvidence\ICP-ARCADE-UNIVERSAL-START-OVERLAY-GMAI-2026-05-20\review.md`

## Predeploy Checks

Executed from canonical project root:

```powershell
node scripts\validate-universal-start-overlay.mjs
node scripts\validate-swing-blade-input-bridge.mjs
node scripts\validate-swing-blade-keymap-resilience.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Check -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Results:

- `validate-universal-start-overlay`: PASS
- `validate-swing-blade-input-bridge`: PASS 44/44
- `validate-swing-blade-keymap-resilience`: PASS 6/6
- Predeploy guard passed canonical root, frontend canister, sanitized payload, deploy identity, and controller checks.

## Deploy

Executed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Deployed asset:

- Key: `/index.html`
- identity SHA256: `93b4eefe1a9c25f6193eed7efadbec5b7b0e035efa880c322056081fcf248dc2`
- gzip SHA256: `53d01a62da0f8b1aa3e162651b7d82980ff11974b9c20b383d49892839067406`
- identity bytes: `1179921`
- gzip bytes: `271082`

The deploy script stored both identity and gzip encodings and verified live raw `/index.html` identity SHA.

## Postdeploy Verification

Live verification URLs:

- `https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html?verify=universal-start-20260520`
- `https://mprew-viaaa-aaaah-quola-cai.icp0.io/?verify=universal-start-20260520`

Results:

- raw SHA256: `93b4eefe1a9c25f6193eed7efadbec5b7b0e035efa880c322056081fcf248dc2`
- icp0 SHA256: `93b4eefe1a9c25f6193eed7efadbec5b7b0e035efa880c322056081fcf248dc2`
- Live raw content contains `arcadeStartOverlay`: yes
- Live raw content contains `universal-start-20260520`: yes
- Live raw content contains `activateArcadeStartOverlay`: yes
- Live raw content contains `arcade-start`: yes
- Live icp0 content contains `arcadeStartOverlay`: yes
- Live icp0 content contains `universal-start-20260520`: yes

## Boundaries

- No backend deploy.
- No ticket payout logic changed.
- No broker, trading, or external account access.
- No legacy frontend canister deploy.
- No canister controller change.

## Status

Deployed and live-verified.
