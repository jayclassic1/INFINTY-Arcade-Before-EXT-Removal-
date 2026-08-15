# Infinity Arcade Dirty Tree Cleanup Implementation Plan

> **For execution:** Use local Jmai/Codex execution for read-only classification and preserve-first cleanup. Use subagent-driven-development only if later code implementation is split out.

**Goal:** Cleanly segment the current Infinity Arcade / Swing Blade dirty tree so frontend source, deploy artifacts, durable evidence, and raw backups are not mixed before any future deploy packet.

**Architecture:** Treat cleanup as lane separation, not deletion. Source and deploy-package changes must be reviewed together; durable evidence stays in concise docs; raw backup/snapshot material must move out of ordinary repo dirt or be intentionally ignored after preservation.

**Tech Stack:** Git, PowerShell, Node.js validators, Infinity Arcade static frontend, ICP deploy-readiness control plane.

---

## Segment Model

- `project_source`: active frontend/game/test changes that may become a commit.
- `task_evidence`: concise review/deploy notes under `docs/runbooks` or `docs/plans`.
- `external_backup`: raw predeploy HTML backups and canister snapshot/memory/module files.
- `scratch_temp`: generated local helper output only; should not remain as repo dirt.

## Task 1: [JMAI] Freeze The Current Evidence

**Files:**
- Read: `index.html`
- Read: `.deploy/frontend-public/index.html`
- Read: `games/swing-blade/index.html`
- Read: `scripts/test-ticket-jackpot-tiers-phase3-frontend-history.mjs`
- Read: `scripts/test-ticket-pool-visibility.mjs`

**Steps:**
1. Run `git status --short -- workspaces/jmai/dapps/infinity-arcade-Jay`.
2. Run `git diff --stat -- workspaces/jmai/dapps/infinity-arcade-Jay`.
3. Confirm root `index.html` and `.deploy/frontend-public/index.html` are identical with `git diff --no-index`.

**Success criteria:** A chat/report summary identifies active modified files and whether root/deploy HTML are synchronized.

## Task 2: [JMAI] Classify Active Source Changes

**Files:**
- Review: `index.html`
- Review: `.deploy/frontend-public/index.html`
- Review: `games/swing-blade/index.html`
- Review: `scripts/test-ticket-jackpot-tiers-phase3-frontend-history.mjs`
- Review: `scripts/test-ticket-pool-visibility.mjs`

**Steps:**
1. Inspect diff hunks for shell/card/jackpot UI changes.
2. Inspect diff hunks for Swing Blade launch-screen changes.
3. Run focused validators:
   - `node scripts/validate-swing-blade-start-helper.mjs`
   - `node scripts/validate-swing-blade-neon-arcade-noir.mjs`
   - `node scripts/test-ticket-pool-visibility.mjs`
   - `node scripts/test-ticket-jackpot-tiers-phase3-frontend-history.mjs`
   - `git diff --check -- workspaces/jmai/dapps/infinity-arcade-Jay`

**Success criteria:** Each modified source/test file is labeled `keep for review`, `needs repair`, or `revert candidate`. Failed validators are explained by cause.

## Task 3: [JMAI] Classify Evidence Files

**Files:**
- Review: `docs/plans/2026-05-11-*.md`
- Review: `docs/runbooks/*.md`
- Review: `scripts/validate-swing-blade-*.mjs`

**Steps:**
1. Read the first section of each untracked markdown file.
2. Mark concise review/deploy notes as `task_evidence`.
3. Mark reusable validators as `project_source`.
4. Mark bulky raw backups as `external_backup`.

**Success criteria:** Every untracked non-binary file has a lane and recommended action.

## Task 4: [JMAI] Preserve Raw Backups Before Any Cleanup

**Files:**
- Source candidate: `.releases/snapshots/pifyq-pre-replace-2026-04-30-000c/*`
- Source candidate: `docs/plans/live-index-backups/mprew-index-20260511T190145Z.predeploy.html`

**Steps:**
1. Run the filesystem alias checker before any move/delete cleanup if available:
   - `node scripts/plan-openclaw-filesystem-aliases.mjs --check`
2. Resolve absolute source and backup destination paths.
3. Copy raw backups to the configured evidence/backup root, preserving names and sizes.
4. Verify copied sizes and hashes.
5. Only after verification, ask for explicit approval before removing the repo-local raw backup files.

**Success criteria:** Raw backups are preserved outside normal source control, with size/hash proof. Repo-local removal is not performed without a separate explicit approval.

## Task 5: [JMAI] Produce Cleanup Decision Packet

**Files:**
- Write/read: `docs/plans/2026-05-23-dirty-tree-cleanup-plan.md`

**Steps:**
1. Summarize active source files to commit/review.
2. Summarize evidence files to keep.
3. Summarize backup files to archive/remove after approval.
4. State deploy readiness blockers that remain.

**Success criteria:** The final packet gives one recommended next action per segment and no deploy is attempted.

## Task 6: [GMAI] Review Gate Before Deploy Readiness Is Claimed

**Files:**
- Review future cleanup commit and exact changed files.

**Steps:**
1. Run Gmai review only after source/evidence decisions are committed or explicitly stashed.
2. Require `APPROVE`, `REVISE REQUIRED`, or `BLOCKED`.
3. Rerun ICP deploy readiness after review passes.

**Success criteria:** No deploy-ready claim is made until the tree is clean enough for the ICP gate and Gmai has approved the relevant source package.

## Current Recommended Actions

1. Keep active source changes together for review: root/deploy `index.html`, Swing Blade game HTML, and the two ticket/jackpot tests.
2. Keep concise runbooks and reusable validators if they support the active source package.
3. Preserve raw `.releases` snapshot files and large predeploy HTML outside normal repo dirt; remove repo-local copies only after explicit approval.
4. Do not deploy until cleanup, review, and ICP readiness pass.

## Execution Notes - 2026-05-23

### Completed Preserve-First Actions

- Alias check passed before cleanup planning: `node C:\Users\Jesse\.openclaw\scripts\plan-openclaw-filesystem-aliases.mjs --check` returned `ok: true`, `blockers: 0`.
- Raw backup artifacts were copied, not removed, to:
  - `C:\Users\Jesse\.openclaw\backups\infinity-arcade\dirty-tree-preserve-20260523T184600Z`
- Backup manifest:
  - `C:\Users\Jesse\.openclaw\backups\infinity-arcade\dirty-tree-preserve-20260523T184600Z\manifest.json`
- Copied artifacts: 5 files, all size/hash verified.

### Segment Decisions From Audit

- Keep for source/package review:
  - `index.html`
  - `.deploy/frontend-public/index.html`
  - `games/swing-blade/index.html`
  - `scripts/test-ticket-jackpot-tiers-phase3-frontend-history.mjs`
  - `scripts/test-ticket-pool-visibility.mjs`
  - `scripts/validate-swing-blade-start-helper.mjs`
  - `scripts/validate-swing-blade-neon-arcade-noir.mjs`
- Keep as durable task evidence unless superseded by a reviewer:
  - concise `docs/runbooks/*.md` review/deploy notes
  - concise `docs/plans/2026-05-11-*.md` review/deploy notes
- Repo-local removal candidates after explicit approval, now externally preserved:
  - `.releases*/snapshots*/pifyq-pre-replace-2026-04-30-000c/*`
  - `docs/plans/live-index-backups/mprew-index-20260511T190145Z.predeploy.html`

### Validation Results

- `node scripts/validate-swing-blade-start-helper.mjs`: PASS 18/18.
- `node scripts/test-ticket-pool-visibility.mjs`: PASS.
- `node scripts/test-ticket-jackpot-tiers-phase3-frontend-history.mjs`: PASS.
- `git diff --check -- workspaces/jmai/dapps/infinity-arcade-Jay`: no whitespace errors; LF/CRLF warnings only.
- `node scripts/validate-swing-blade-neon-arcade-noir.mjs`: FAIL 1/19 because `.deploy/frontend-public/index.html` is modified. Root `index.html` and deploy copy are byte-identical, so this is a packaging/governance decision, not a proved UI failure.

### Next Gate

Operator approved repo-local removal of the externally preserved raw backup artifacts at 2026-05-23 14:54 ET.

Removed from repo-local dirt after rechecking source and backup hashes against the manifest:

- `.releases*/snapshots*/pifyq-pre-replace-2026-04-30-000c/metadata.json`
- `.releases*/snapshots*/pifyq-pre-replace-2026-04-30-000c/stable_memory.bin`
- `.releases*/snapshots*/pifyq-pre-replace-2026-04-30-000c/wasm_memory.bin`
- `.releases*/snapshots*/pifyq-pre-replace-2026-04-30-000c/wasm_module.bin`
- `docs/plans/live-index-backups/mprew-index-20260511T190145Z.predeploy.html`

Also removed empty directory:

- `docs/plans/live-index-backups`

Do not revert files, stage files, commit, or deploy until the operator approves the next cleanup action.
