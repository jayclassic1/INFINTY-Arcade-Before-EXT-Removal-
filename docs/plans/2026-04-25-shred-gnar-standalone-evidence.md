# Shred Gnar Standalone Page Evidence

Date: 2026-04-25 / 2026-04-26 UTC
Project: ICP-ARCADE / Infinity Arcade
Deploy authorized: false

## User request

- Remove Shred Gnar from the Showroom.
- The only games shown in Showroom should be games uploaded through zip/submission flow.
- Keep Shred Gnar on its own page and provide the direct web link for building/testing.

## Changes

- Removed the hardcoded `shredGnarLocalLauncher` / `LOCAL TEST PATH` block from the Showroom in `index.html`.
- Kept the standalone Shred Gnar game files at `games/skate-apocalypse/`.
- Updated `scripts/test-shred-gnar-local-entry.mjs` so it now verifies:
  - Shred Gnar is not hardcoded into Showroom.
  - The standalone Shred Gnar page/assets still exist.

## Standalone link

After deploy, the Shred Gnar build page will be:

```text
https://mprew-viaaa-aaaah-quola-cai.icp0.io/games/skate-apocalypse/
```

## Validation

Commands run:

```powershell
node scripts\test-shred-gnar-local-entry.mjs
node scripts\validate-wallet-globals.mjs
node scripts\validate-my-collection-buttons.mjs
node scripts\build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Results:

```text
shred-gnar-standalone-page ok
Wallet globals validation PASSED (5/5)
My Collection button validation PASSED (5/5)
Frontend publish payload written to .deploy/frontend-public
Files: 35
Predeploy check passed. Verified frontendCanister=mprew-viaaa-aaaah-quola-cai and frontendDeploySource=.deploy/frontend-public.
Sanitized payload files: 35
```

## Deploy status

Not deployed yet. Requires review and/or explicit deploy approval before publishing to `mprew`.
