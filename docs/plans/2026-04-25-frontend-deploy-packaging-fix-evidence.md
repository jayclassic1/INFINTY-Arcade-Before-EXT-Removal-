# Frontend Deploy Packaging Fix Evidence

Date: 2026-04-25
Project: ICP-ARCADE / Infinity Arcade
Deploy authorized: false

## Summary

Fixed the Phase 5 deploy-readiness blocker by making the frontend deploy payload explicit and sanitized.

Production frontend deploys must now use:

```powershell
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Then dry-run/deploy from:

```text
.deploy/frontend-public
```

Do not deploy the project root directly.

## What changed

- Added `scripts/build-frontend-publish.mjs` to generate a deterministic public-only frontend payload.
- Added `scripts/test-frontend-publish.mjs` to prove the payload contains expected public assets and excludes internal paths.
- Hardened `scripts/predeploy-check.ps1` so it requires the generated payload, verifies `frontendDeploySource`, requires `index.html` and `manifesto.txt`, and rejects forbidden internal paths.
- Updated `deploy-manifest.json` with the sanitized `frontendDeploySource` and corrected canonical source path.
- Updated `.deployignore` as defense-in-depth if someone accidentally points tooling at the root.
- Updated `.gitignore` so generated `.deploy/` output stays untracked.
- Updated deploy/root docs to state the new rule clearly.

## Sanitized payload contents

Generated payload contains 35 files:

```text
arcades-flow.jpg
artists-gashapon-system.png
artists-nft-revenue-splits.webp
backroom-bg.jpg
boardroom.jpg
dao-flow-overview.jpg
dao-flow-overview.png
deploy-manifest.txt
dfinity-bundle.js
digitar-base.png
digitar-mask.png
forums-bg.jpg
fullcatalog.jpg
games/infection/audio/death-loop.mp3
games/infection/audio/gameplay-loop.mp3
games/infection/audio/menu-loop.mp3
games/infection/index.html
games/skate-apocalypse/game.js
games/skate-apocalypse/index.html
games/skate-apocalypse/styles.css
games/swing-blade/index.html
gashapon-bg.jpg
index.html
landing-v6.jpg
legal-privacy.md
legal-tos.md
manifesto-bg.jpg
manifesto-popup-bg.jpg
manifesto.txt
manual-page1.jpg
manual-page2.jpg
mycollection.jpg
prizebooth.jpg
showroom-v3.jpg
the-hole-approved-bg.jpg
```

Forbidden internal directories are excluded from the payload:

- `backend/`
- `docs/`
- `scripts/`
- `tasks/`
- `.openclaw-review/`
- `.git/`
- `.deploy/`
- `node_modules/`

## Validation

Commands run from `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`:

```powershell
node scripts\test-frontend-publish.mjs
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
node scripts\validate-creator-earnings-phase1.mjs
node scripts\validate-creator-earnings-phase2.mjs
node scripts\validate-creator-earnings-phase3.mjs
node scripts\validate-creator-earnings-phase4.mjs
```

Results:

- Frontend publish test: passed.
- Publish generation: passed, 35 public files generated.
- Predeploy check: passed; verified `frontendCanister=mprew-viaaa-aaaah-quola-cai` and `frontendDeploySource=.deploy/frontend-public`.
- Phase 1 copy/IDL checks: passed.
- Phase 2 claim safety checks: passed `11/11`.
- Phase 3 unit cleanup checks: passed `8/8`.
- Phase 4 dashboard polish checks: passed `10/10`.

## Asset diff dry run

`icp_diff_assets` was run against the exact sanitized source directory:

```text
source_dir=C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\.deploy\frontend-public
canister_id=mprew-viaaa-aaaah-quola-cai
```

Result:

```text
to_create: 1
  /deploy-manifest.txt
to_update: 2
  /index.html
  /manifesto.txt
to_delete: 0
unchanged: 32
```

No backend, docs, scripts, tasks, or review files appear in the sanitized asset diff.

## Residual risk

- `deploy-manifest.txt` is a public generated file listing the deployed payload. It is intentionally non-secret and can be removed later if Gmai prefers zero new public manifest files.
- No deployment was performed in this step.

## Next step

Send this packaging fix through Gmai re-review. If approved, the only remaining gate is explicit Jay approval before any frontend deploy to `mprew-viaaa-aaaah-quola-cai`.
