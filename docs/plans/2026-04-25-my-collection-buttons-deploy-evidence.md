# My Collection Button Cleanup Deploy Evidence

Date: 2026-04-25 / 2026-04-26 UTC
Project: ICP-ARCADE / Infinity Arcade
Frontend canister: `mprew-viaaa-aaaah-quola-cai`
Commit: `d63463795838b4cd8b8e6259a956b2d2162bbce5`
Approval: Jay replied `approve` after Gmai approval for the UI-only change.

## Result

Deployed the My Collection UI-only change to the active frontend canister.

The My Collection page now hides:

- `Gashapon Tickets`
- `Mint NFT`

It keeps:

- `Scan`

## Gates before deploy

- Gmai review: `tasks/gmai-my-collection-buttons-review-20260425/review.md` verified PASS/APPROVE.
- ICP auth: authenticated as `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`.
- Network: `ic` / `https://icp-api.io`.
- Build env: ready.

## Commands / evidence

```powershell
node scripts\validate-my-collection-buttons.mjs
node scripts\build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Results:

```text
My Collection button validation PASSED (5/5)
Frontend publish payload written to .deploy/frontend-public
Files: 35
Predeploy check passed. Verified frontendCanister=mprew-viaaa-aaaah-quola-cai and frontendDeploySource=.deploy/frontend-public.
```

Pre-deploy asset diff against sanitized payload:

```text
to_create: 0
to_update: 1 (/index.html)
to_delete: 0
unchanged: 34
```

Deploy result:

```text
icp_deploy_frontend success=true
files_uploaded=35
total_files=35
uploaded_bytes=11980581
created=0
updated=35
failed=0
production=https://mprew-viaaa-aaaah-quola-cai.icp0.io
```

Post-deploy checks:

```text
icp_diff_assets against .deploy/frontend-public:
to_create: 0
to_update: 0
to_delete: 0
unchanged: 35
```

Live homepage check:

- `https://mprew-viaaa-aaaah-quola-cai.icp0.io/` returned HTTP 200 with `INFINITY ARCADE` content.

## Notes

Deployment used only the sanitized `.deploy/frontend-public` payload. The project root and legacy arcade trees were not deployed.
