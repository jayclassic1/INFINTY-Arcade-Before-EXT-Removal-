# PROJECT.md — Infinity Arcade (Jay Unified Root)

**Project ID:** ICP-ARCADE  
**Project Name:** Infinity Arcade (Jay Nolan)  
**Unified Cutover Root:** `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
**Status:** Active production source; fresh-start migration complete and wallet pass good on 2026-04-25

---

## Purpose

This directory is the accepted canonical active production source for Infinity Arcade.

It resolves the former split-source problem between:
- former canonical frontend tree: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade`
- former backend/source-of-truth tree: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\icp-arcade`

The fresh-start migration completed on 2026-04-25, and the human wallet pass was good on 2026-04-25. Future work, verification, and deploy flows should use this unified root unless explicit fallback/rollback work is approved.

---

## Production truth

- Active production frontend asset canister: `mprew-viaaa-aaaah-quola-cai`
- Active production backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Public URL: `https://mprew-viaaa-aaaah-quola-cai.icp0.io`
- Fresh-start migration completed: 2026-04-25
- Human wallet pass: good on 2026-04-25
- Registry alignment: `ICP-ARCADE` already points to `dapps/infinity-arcade-Jay`; do not edit the registry for this lock-docs pass.
- Legacy frontend `ewgfh-vqaaa-aaaah-qtixa-cai` and legacy backend `sympv-naaaa-aaaad-qktuq-cai` are fallback/reference-only until explicit retirement approval.

## Source-of-truth lineage

### Frontend lineage
This unified root now carries the accepted deploy-safe frontend lineage previously sourced from:
- `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade`

Key frontend findings retained in this root:
- `index.html` lineage from `dapps/infinity-arcade/index.html`
- deploy-safe metadata and public-facing UI fixes are preserved here
- backed-only public ticket-pool display lineage is preserved here

### Backend lineage
This unified root now carries the accepted backend/accounting truth previously sourced from:
- `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\icp-arcade\backend`

Key backend findings retained in this root:
- `backend/main.mo` is the authoritative backend/accounting source
- backend scripts and ICP project config are preserved under `backend/`

### Repo hygiene / root control
Root hygiene is merged into this active source tree. Future hygiene changes should be made in this root only, with legacy trees treated as reference/fallback until retirement is explicitly approved.

---

## Canonical rules for this new root

1. Do **not** delete the old trees yet.
2. Treat this folder as the canonical active production source for future work.
3. Deploy only from this root to the active production canisters unless explicit fallback/rollback work is approved.
4. Preserve deploy-safe frontend lineage and authoritative backend truth here.
5. Public ticket values must remain backed-only.
6. Legacy retirement requires explicit approval; no deletion or irreversible cleanup is implied by this document.

---

## Intended structure target

Current canonical structure inside this root:
- retained frontend app files at the root, including the active production `index.html`
- `backend/` for Motoko backend source and related scripts/config
- `games/` for active canonical game content
- canonical docs / metadata files

The root is now accepted as the active source tree. Later structure cleanup should be stabilization work, not a prerequisite to production truth.

---

## Phase progress

### Phase A — COMPLETE
The following findings have been reviewed and confirmed against both trees:
- the project was formerly split across two different local roots
- latest frontend winner source before unification = `dapps/infinity-arcade`
- backend/accounting winner source before unification = `dapps/icp-arcade/backend`
- shared critical file winners reviewed manually:
  - `index.html` winner = `dapps/infinity-arcade/index.html`
  - `.gitignore` base = `dapps/icp-arcade/.gitignore` plus `releases/`
- merge manifest written and reviewed

### Phase B — COMPLETE
This root was populated with the winning structure and accepted as the canonical active production source.

Completed in Phase B:
1. imported the winning frontend tree from `dapps/infinity-arcade`
2. imported backend source-of-truth under `backend/` from `dapps/icp-arcade/backend`
3. applied merged root hygiene with `.gitignore` based on `icp-arcade` plus `releases/`
4. retained canonical deploy metadata and root structure docs in the new root
5. completed fresh-start production migration on 2026-04-25
6. confirmed human wallet pass good on 2026-04-25

### Phase C — COMPLETE
Tooling alignment is complete for the active production truth:
1. registry already points `ICP-ARCADE` to `dapps/infinity-arcade-Jay`
2. active production frontend canister is `mprew-viaaa-aaaah-quola-cai`
3. active production backend canister is `pifyq-raaaa-aaaab-agrqq-cai`
4. public production URL is `https://mprew-viaaa-aaaah-quola-cai.icp0.io`

### Remaining later work
- stabilization checks after production traffic/use
- cautious legacy-retirement planning for `ewgfh-vqaaa-aaaah-qtixa-cai` and `sympv-naaaa-aaaad-qktuq-cai`
- no deletion, canister mutation, or registry edit without explicit approval

---

## Reference artifacts

Supporting plan/docs already written:
- `docs/plans/2026-04-23-icp-arcade-unified-root-cutover-plan.md`
- `docs/plans/2026-04-23-icp-arcade-merge-manifest.md`
- `docs/plans/2026-04-23-phase-b-file-review.md`

---

## Future build notes

### Admin treasury vs economy metrics

The admin Treasury card currently shows token/ticket numbers from `getTotalCirculation()` when treasury backend methods are pending. Those values are economy-wide circulation totals, not treasury-held balances. While there is only one active player/admin account, those totals can match Jay's personal Tokens/Tickets and appear personal.

Future admin build should separate these concepts clearly:
- **Treasury:** ICP balance, operating treasury, escrow, withdrawable/sweep state, backend method status.
- **Economy:** total Tokens circulating, total Tickets circulating, signed-up players, active players.

Do not label economy circulation as treasury holdings. If treasury token/ticket holdings do not exist as real backend buckets yet, show them as unavailable or move them out of the Treasury card until backend accounting supports them.
