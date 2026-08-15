# Infinity Arcade Production Stabilization and Legacy-Retirement Checklist

Date: 2026-04-25
Status: planning/control checklist only

This document records the non-destructive stabilization path after the production docs lock and wallet pass. It does **not** authorize deleting, moving, deploying, mutating canisters, or retiring any legacy canister.

## Current production truth

- Production frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Production backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Public production URL: `https://mprew-viaaa-aaaah-quola-cai.icp0.io`
- Wallet validation: Jay confirmed wallet pass good on 2026-04-25.

## Stabilization window acceptance checks

Complete these checks during the stabilization window before any legacy-retirement decision:

- [ ] Homepage loads from `https://mprew-viaaa-aaaah-quola-cai.icp0.io` without a blank screen, console-fatal runtime error, or redirect to a legacy canister.
- [ ] Manifesto page/section is reachable and displays expected production copy and styling.
- [ ] Shred Gnar route is reachable and launches the expected production game path.
- [ ] Wallet connect completes successfully with the current production frontend and does not require a legacy URL.
- [ ] Backend smoke queries against `pifyq-raaaa-aaaab-agrqq-cai` return expected healthy responses for read-only status/catalog/session flows.
- [ ] Served runtime does not contain old runtime IDs in active paths, especially `ewgfh-vqaaa-aaaah-qtixa-cai` or `sympv-naaaa-aaaad-qktuq-cai`.
- [ ] User-reported regressions are collected, triaged, and either resolved or explicitly accepted by the owner before any retirement step.

## Rollback and fallback posture

- `ewgfh-vqaaa-aaaah-qtixa-cai` is reference/fallback only.
- `sympv-naaaa-aaaad-qktuq-cai` is reference/fallback only.
- Do not call, deploy to, uninstall, reinstall, delete, clean up, or otherwise mutate either legacy canister unless there is explicit approval for that exact action.
- Keep legacy references available for comparison, archival recovery, or emergency fallback planning only.
- If production validation fails, pause retirement planning and use the documented rollback plan instead of improvising canister changes.

## Legacy-retirement preconditions

All preconditions must be satisfied before asking for legacy-retirement approval:

- [ ] Clean validation window completed with no unresolved launch-blocking regression.
- [ ] Owner approval captured for the specific retirement scope and target canisters.
- [ ] Final backup/snapshot evidence captured and linked for every canister or asset set in scope.
- [ ] Canister controller and status checks completed for `mprew-viaaa-aaaah-quola-cai`, `pifyq-raaaa-aaaab-agrqq-cai`, `ewgfh-vqaaa-aaaah-qtixa-cai`, and `sympv-naaaa-aaaad-qktuq-cai`.
- [ ] Asset inventory/diff produced for production versus legacy references, with any unique legacy asset accounted for.
- [ ] Rollback plan written, including owner-visible criteria for when to restore or re-enable fallback.
- [ ] Gmai review or equivalent explicit sign-off completed for the retirement plan before execution.

## Do not do yet

- Do not delete legacy canisters.
- Do not uninstall or reinstall any canister.
- Do not perform broad cleanup, sweeping moves, or irreversible archival changes.
- Do not change the deploy target away from `mprew-viaaa-aaaah-quola-cai` without explicit approval.
- Do not touch legacy paths except for archival recovery by explicit request.
- Do not treat this checklist as authorization to retire `ewgfh-vqaaa-aaaah-qtixa-cai` or `sympv-naaaa-aaaad-qktuq-cai`.

## Next recommended order

1. Monitor and validate production behavior on `mprew-viaaa-aaaah-quola-cai` with backend `pifyq-raaaa-aaaab-agrqq-cai`.
2. Gather evidence for the stabilization window checks, including wallet connect, backend smoke query results, route checks, and absence of old runtime IDs.
3. Ask the owner for explicit approval only after the evidence package is clean and reviewed.
4. Retire references safely later, under a separate approved task with backups, status checks, asset inventory/diff, and rollback plan attached.
