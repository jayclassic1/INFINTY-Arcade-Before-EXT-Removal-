# Infinity Arcade Jackpot Tiers Phase 4 Deploy Readiness

Task: `icp-arcade-jackpot-tiers-phase4-deploy-readiness-20260513`  
Project: ICP-ARCADE / Infinity Arcade (Jay Nolan)  
Active backend: `pifyq-raaaa-aaaab-agrqq-cai`  
Active frontend: `mprew-viaaa-aaaah-quola-cai`  
Deploy: **not performed**

## Summary

Prepared deploy-readiness guardrails for the reviewed ticket jackpot tier release. This phase does not upgrade or upload canisters; it hardens target validation and records the release gate status before any future deploy approval.

## Changes

- Hardened `deploy-manifest.json` legacy policy from reference-only to quarantined-reference-only.
- Added explicit denied validation targets:
  - `icparcade.dev`
  - `ewgfh-vqaaa-aaaah-qtixa-cai`
- Hardened `scripts/predeploy-check.ps1` to refuse:
  - wrong project root
  - non-active frontend target
  - quarantined legacy frontend target
  - wrong manifest canonical source
  - wrong frontendDeploySource
  - forbidden/internal payload paths
  - any sanitized payload file containing denied target/domain references
- Removed stale `icparcade.dev` references from legal docs so sanitized payload passes the new full-payload scan.
- Confirmed deploy source remains `.deploy/frontend-public` and active frontend remains `mprew-viaaa-aaaah-quola-cai`.

## Gmai revision

Initial Gmai review returned `REVISE REQUIRED` because the guard scanned only `index.html`, while the sanitized payload still contained `icparcade.dev` in `legal-privacy.md` and `legal-tos.md`.

Revision completed:

- predeploy guard now scans every sanitized payload file using byte-level ASCII decoding.
- legal docs no longer reference the abandoned `icparcade.dev` validation domain.
- negative proof confirms the guard fails closed when `icparcade.dev` is injected into `.deploy/frontend-public/legal-tos.md`.
- negative proof confirms the guard fails closed for the quarantined legacy frontend canister.

## Verification

Passed:

- `git diff --check -- deploy-manifest.json scripts/predeploy-check.ps1 legal-privacy.md legal-tos.md docs/runbooks/infinity-arcade-jackpot-tiers-phase4-deploy-readiness-2026-05-13.md`
- `node scripts\build-frontend-publish.mjs`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1`
- negative proof: injected `icparcade.dev` into `.deploy/frontend-public/legal-tos.md`; predeploy failed closed
- negative proof: ran predeploy with `-ExpectedCanister ewgfh-vqaaa-aaaah-qtixa-cai`; predeploy failed closed
- `node scripts\test-ticket-jackpot-phase0-quarantine.mjs`
- `node scripts\test-ticket-jackpot-phase1.mjs`
- `node scripts\test-ticket-jackpot-admin-thresholds.mjs`
- `node scripts\test-ticket-jackpot-tiers-phase1-config.mjs`
- `node scripts\test-ticket-jackpot-tiers-phase2-payouts.mjs`
- `node scripts\test-ticket-jackpot-tiers-phase3-frontend-history.mjs`
- `node scripts\validate-paid-session-score-flow.mjs`
- `node scripts\test-ticket-payout-config.mjs`
- `node scripts\test-model-a-chain.mjs`
- `npm run backend:check`

Earlier identity/canister readiness also passed:

- Deploy identity guard passed for `mcp-identity` principal `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`.
- Guard verified encrypted password storage.
- Guard verified controller status on backend `pifyq-raaaa-aaaab-agrqq-cai` and frontend `mprew-viaaa-aaaah-quola-cai`.

## Deploy gate

Ready for Gmai re-review. After approval, live deployment still requires explicit deploy approval and a backend snapshot before upgrade.

No deploy, upgrade, upload, delete, or snapshot was performed in this phase.
