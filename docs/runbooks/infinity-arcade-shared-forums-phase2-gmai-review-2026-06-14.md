# Gmai Review: Infinity Arcade Shared Forums / Proposals Phase 2

Task: `review-infinity-arcade-shared-forums-phase2`
Project: `ICP-ARCADE`
Reviewed commit: `3c7c96cd35f0740ad74b60ccda3104d98a877692`
Target canister: `pifyq-raaaa-aaaab-agrqq-cai`
Deploy authorized: `false`
Output lane: `task_evidence`
Trace: `887a0777d113475dbdd291a17cc2470c`

## Verdict

REVISE REQUIRED

## Evidence checked

- Contract/scope preflight: `verify_write_scope` approved writing only `docs/runbooks/infinity-arcade-shared-forums-phase2-gmai-review-2026-06-14.md` under the allowed project root.
- System health preflight: safety loaded; no open provider circuits; system overall degraded due stale heartbeat/low recent verification pass rate, not a blocker for local review.
- Git evidence:
  - `git rev-parse --show-toplevel` -> `C:/Users/Jesse/.openclaw`
  - `git rev-parse HEAD` -> `3c7c96cd35f0740ad74b60ccda3104d98a877692`
  - `git show --name-status --format=fuller --no-renames 3c7c96cd35f0740ad74b60ccda3104d98a877692 -- ...` showed changed project files.
  - Inspected relevant diff/source for `backend/main.mo`, `index.html`, `package.json`, `scripts/validate-real-icp-api-surface.mjs`, `scripts/validate-shared-forums-phase2.mjs`, and the summary runbook.
- Targeted source checks:
  - Backend shared forum/proposal type and API additions around `backend/main.mo:541-548` and `backend/main.mo:3990-4223`.
  - Frontend forum/proposal IDL and helpers around `index.html:7837-7904`, `index.html:14704-14714`, and `index.html:14935-15746`.
  - Summary runbook at `docs/runbooks/infinity-arcade-shared-forums-phase2-summary-2026-06-14.md`.

## Tests run

- `npm run validate:shared-forums-phase2` -> passed.
- `npm run backend:check` -> passed; guard passed and canisters built successfully.
- `npm run test:real-icp-api-surface` -> passed 9/9.
- `git diff --check 3c7c96cd35f0740ad74b60ccda3104d98a877692^ 3c7c96cd35f0740ad74b60ccda3104d98a877692 -- <changed files>` -> passed/no output.
- `Select-String` for raw deploy/live mutation terms in changed source/validator (`dfx`, `install_code`, `create_canister`, `icp deploy`) -> no matches in checked files.

## Issues

1. **Frontend DAO stats IDL is incompatible with the new backend `DaoStats` record.**
   - Backend returns `{ proposals; activeProposals; badgeHolders; forumThreads }` (`backend/main.mo:252-257`, `backend/main.mo:4216-4222`).
   - Frontend declares `daoStats` as `{ totalProposals; activeProposals; passedProposals; totalVpHolders }` (`index.html:7904`) and reads `stats.totalProposals` / `stats.totalVpHolders` in `loadDaoDashboard` (`index.html:11002-11004`).
   - This is likely to break Candid decode and/or render `NaN`/missing dashboard stats after upgrade. The validator only checks method presence, not record shape parity.

2. **DAO forum read access remains backend-public and the residual gap is not documented.**
   - `createForumThread` and `addForumReply` gate DAO-section writes using `hasDaoAccess`, but `getForumThreads(section)` returns DAO-section threads to any caller and is a query without caller gate (`backend/main.mo:4021-4024`).
   - If restricted DAO forum visibility is intended, this needs a server-side caller-aware query/update path or a clear residual-risk note that DAO forum reads are publicly readable on-chain despite frontend gating.

3. **Summary runbook is slightly inaccurate/incomplete.**
   - It omits `scripts/validate-real-icp-api-surface.mjs` from the changed-file list even though the reviewed commit modifies it.
   - It reports `npm run backend:mops:check` as passed, but the handoff evidence only requested/confirmed `validate:shared-forums-phase2`, `backend:check`, and `test:real-icp-api-surface`; I did not rerun `backend:mops:check` during this review.

## Positive findings

- Backend additions are additive to stable state and do not alter existing stable record shapes; forum/proposal state is stored in new stable arrays/counters.
- Public forums and proposal/vote storage are global/shared in backend state rather than per-browser localStorage only.
- Proposal creation, voting, and proposal replies include server-side principal/voting-power/admin checks.
- No accidental `async async` pattern was found by targeted search.
- The new validation script is useful as a smoke/static check for method presence and raw deploy-tool avoidance, but it needs record-shape and access-gap checks before it can fully gate this feature.
- No deploy/live mutation path was introduced in the checked source, and no deploy/live mutation was run during review.

## Residual risk

- This remains local-only and undeployed; live upgrade still needs separate stable compatibility/preflight and explicit approval.
- Forum/proposal text and image payload sizes are not bounded server-side in this phase; this may become a storage/cycle moderation concern.
- Existing frontend `closeProposal` IDL/call appears to expect a backend method not present in the reviewed backend; not newly introduced by this commit, but still a DAO admin-flow risk if exercised.

## Next action

Revise before acceptance: align `daoStats` backend/frontend record shape and validator coverage, either gate or document DAO forum read visibility, and correct the summary runbook changed-file/test evidence.