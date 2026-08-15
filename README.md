# INFINITY Arcade

Canonical source export prepared from `dapps/infinity-arcade-Jay`.

Active local production references at export time:

- Frontend asset canister: `mprew-viaaa-aaaah-quola-cai`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Public URL: <https://mprew-viaaa-aaaah-quola-cai.icp0.io>

Start here:

- `PROJECT.md`
- `PROJECT_OVERVIEW.md`
- `CANONICAL.md`
- `docs/runbooks/infinity-arcade-ai-catchup-scope-2026-06-23.md`

Safety notes:

- This export intentionally excludes generated dependencies, `.dfx`, `.mops`, `.icp`, `.deploy`, `.releases`, tmp/task evidence, logs, zip files, PEM/env files, WASM artifacts, and `canister_ids.json`.
- Frontend publish payload should be regenerated with `node scripts/build-frontend-publish.mjs`.
- Do not deploy or upgrade canisters without fresh live-state verification and explicit approval.
