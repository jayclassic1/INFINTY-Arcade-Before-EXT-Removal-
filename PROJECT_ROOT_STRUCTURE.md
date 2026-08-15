# Infinity Arcade Project Root Structure

**Project ID:** ICP-ARCADE  
**Canonical Root:** `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`  
**Status:** Active canonical source for Jay Nolan's Infinity Arcade frontend and project-facing artifacts.

---

## Purpose of this file

This file is the human-readable structure contract for the current canonical root.

It answers:
- what this root is for
- what belongs here
- what should not be treated as canonical here
- where future work should land inside this root

---

## What this root currently owns

### 1. Canonical frontend app
Core player/admin frontend lives here.

Primary file:
- `index.html`

This is the live-facing frontend shell and current source of truth for:
- game details UI
- admin tools UI
- funding UI
- backed-only public ticket-pool display
- deploy-safe web assets

### 2. Frontend game assets and media
Examples:
- `backroom-bg.jpg`
- `boardroom.jpg`
- `showroom-v3.jpg`
- `prizebooth.jpg`
- `dao-flow-overview.*`
- `games/swing-blade/index.html`
- `games/infection/...`

These are part of the active frontend experience when referenced by the canonical shell.

### 3. Canonical deploy metadata and safety docs
Examples:
- `CANONICAL.md`
- `README_CANONICAL_DEPLOY.md`
- `ROLLBACK.md`
- `.deployignore`
- `deploy-manifest.json`
- `SESSION_PRICING_POLICY.md`
- `BLACKHOLE_OPTIMIZATION_POLICY.md`

These files define how this tree is treated for safe deploy and recovery.

### 4. Frontend validation scripts
Examples:
- `scripts/predeploy-check.ps1`
- `scripts/test-ticket-pool-visibility.mjs`

These support deploy hygiene and targeted frontend verification.

---

## What this root does **not** currently own cleanly

### Backend accounting source of truth
The deeper backend accounting implementation for legacy ICP Arcade work is **not currently housed cleanly inside this canonical root**.

That means this root is currently strongest as:
- canonical frontend root
- deploy-safe source for production frontend
- project-facing documentation and validation root

And weaker as:
- full-stack single-root source of truth for backend reconciliation work

---

## Current internal structure expectations

### Root-level files
Use root-level files only for:
- canonical docs
- deploy metadata
- globally used frontend shell/assets
- project structure references

Avoid placing scratch scripts, exports, and archives at root unless they are explicitly part of canonical deploy or validation.

### `games/`
Use for game-specific frontend content that belongs in the canonical player-facing experience.

Examples:
- `games/swing-blade/`
- `games/infection/`

Each game subtree should contain only live or intentionally retained canonical game assets/code.

### `scripts/`
Use for canonical validation, migration helpers that are safe to keep, and deploy-support scripts.

Do not treat `scripts/` as a dumping ground for temporary one-off experiments.

### docs/plans (outside this root)
Planning artifacts should continue to live under workspace docs/plans unless there is a project-specific reason to keep them inside this root.

---

## Canonical rules

### Rule 1 — Deploy safety
Production frontend deploys for Infinity Arcade should come from the generated `.deploy/frontend-public/` payload only, after running `node scripts/build-frontend-publish.mjs` and `scripts/predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai`. Do not deploy the project root directly.

### Rule 2 — Public truth
Public UI must show only economically truthful values.

Current enforced UI direction:
- public ticket pool = backed-only display
- raw/internal counters = admin diagnostic only

### Rule 3 — No legacy mixing by accident
Do not casually blend files from older/legacy trees into this root without an explicit merge/cutover pass.

### Rule 4 — Keep structure intentional
Any new major subtree added here should answer one of these roles:
- frontend runtime
- canonical assets
- deploy safety
- validation
- explicitly approved project documentation

---

## Recommended future target structure

If Infinity Arcade remains rooted here long-term, the clean next structure would be:

- `index.html`
- `games/`
- `assets/` (optional future consolidation)
- `scripts/`
- `docs/` (optional project-local docs if desired)
- `CANONICAL.md`
- `PROJECT_ROOT_STRUCTURE.md`

If full-stack consolidation later happens, backend should be brought into a clearly named subtree rather than living outside the project contract.

---

## Current project reality

As of this file:
- this root is the **active canonical frontend root**
- it is the correct place for continued canonical frontend work
- deploy payloads are generated into `.deploy/frontend-public/` so backend/docs/scripts/tasks are not served publicly
- it contains the latest live-backed UI updates already deployed from this source line

---

## Immediate resume guidance

When continuing work in this project root:
1. treat `index.html` as the canonical frontend shell
2. keep player-facing truth aligned with backed-only ticket display rules
3. use this root for frontend changes, validation, and deploy-safe operations
4. do not assume external trees are canonical unless an explicit cutover is being executed
