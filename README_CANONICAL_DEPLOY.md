# Infinity Arcade Canonical Deploy Notes

- Canonical project root: `dapps/infinity-arcade-Jay`
- New frontend asset canister: `mprew-viaaa-aaaah-quola-cai`
- Fresh backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Public URL: `https://mprew-viaaa-aaaah-quola-cai.icp0.io`
- Fresh-start migration completed: `2026-04-25`
- Human wallet pass: good on `2026-04-25`
- Restored from: `incoming/jay-arcade-public-bundle`
- Legacy frontend fallback: `ewgfh-vqaaa-aaaah-qtixa-cai`
- Legacy backend/reference-only: `sympv-naaaa-aaaad-qktuq-cai` — audit/rollback context only; do not call or deploy in normal operation.
- Legacy trees are not deploy-safe.

## Deploy rule

Do **not** deploy the project root directly. Build the explicit public payload first:

```powershell
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

The only intended frontend deploy source is `.deploy/frontend-public/`, generated from allowlisted public files (`index.html`, `manifesto.txt`, legal docs, public media, `dfinity-bundle.js`, and game runtime assets). Dry-runs and deploys should point at that directory, not at `dapps/infinity-arcade-Jay`.

Frontend target remains `mprew-viaaa-aaaah-quola-cai`. Backend work targets `pifyq-raaaa-aaaab-agrqq-cai` only when a task explicitly authorizes backend mutation/deploy work.

## Index-only frontend deploy

Use the index-only path when the only intended live change is `/index.html` (for example, copy/JS/CSS inlined into the shell or a small emergency homepage fix) and the existing asset canister payload should otherwise remain untouched. It is safer than a full asset refresh because it prepares exactly two `store` calls for the same key: `identity` and `gzip`.

Dry-run/check only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1
```

Authorized deploy mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy
```

The wrapper builds `.deploy/frontend-public/`, runs `scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai`, runs `npm run deploy:guard`, generates Candid arg files under `.deploy/index-only/`, and prints the exact `icp canister call mprew-viaaa-aaaah-quola-cai store` commands. In `-Deploy` mode it calls `store` for identity and gzip through `node scripts\run-icp-tool.mjs`, then fetches the raw live `/index.html` with `Accept-Encoding: identity` and compares the SHA256 to the local built file.

Use a full asset refresh only when non-index assets changed (game files, media, `dfinity-bundle.js`, legal docs, or other allowlisted static files). The current full sync route has an asset-property compatibility issue, so prefer index-only for `/index.html`-only changes until the full sync asset-property issue is remediated and signed off.

## Backend predeploy build gate

Backend build/readiness checks use the ICP CLI path, not DFX. `backend/dfx.json` is retained only as legacy reference.

```powershell
npm run backend:guard
npm run backend:mops:check
npm run backend:check
```

The package scripts route ICP tools through `node scripts/run-icp-tool.mjs`, which allowlists `icp`, `mops`, and `ic-wasm` and runs them through WSL so Motoko tooling resolves on the supported path. Active build/deploy scripts must not invoke `dfx`.
## Legacy retirement policy

Keep ewgfh and sympv only as reference/fallback metadata during stabilization. Retire these references later after an explicit clean validation window and human approval.

