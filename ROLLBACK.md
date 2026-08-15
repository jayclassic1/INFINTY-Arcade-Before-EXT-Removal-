# Infinity Arcade Rollback Notes

## Current production path

- Frontend asset canister: `mprew-viaaa-aaaah-quola-cai`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`

## Legacy fallback path

- Previous frontend asset canister: `ewgfh-vqaaa-aaaah-qtixa-cai`
- Previous backend/reference-only canister: `sympv-naaaa-aaaad-qktuq-cai`

Do not delete or mutate the legacy path during stabilization. Treat it as fallback/reference only until the new `mprew` + `pifyq` path has completed a clean validation window.
Reference-only means the ID is preserved for audit/rollback understanding, not for normal deploys, frontend runtime calls, or admin scripts. Retire it later after explicit sign-off.

