# DAO Gaming-Only Revenue Final Product Implementation Plan

> **For execution:** Use the subagent-driven-development skill to implement this plan. Route each task by its ownership tag.

**Goal:** Remove DAO participation from NFT/ticket/gashapon revenue language and align the final product around DAO rewards funded only by gaming revenue.

**Architecture:** Keep the existing gameplay DAO share concepts for ticket and non-ticket games, while separating game ticket pools from DAO member rewards. This pass is primarily frontend/copy/API-surface alignment because the canonical backend currently exposes gameplay DAO split constants but does not show a hardened NFT-to-DAO accounting path. Backend changes should be minimal and limited to comments/metadata unless implementation finds an actual DAO credit path from NFT/gashapon revenue.

**Tech Stack:** Motoko backend (`backend/main.mo`), single-file frontend (`index.html`), project docs under `docs/plans/`.

---

## Current State

- `backend/main.mo` exposes gameplay DAO split constants:
  - `TICKET_GAME_DAO_SHARE = 5`
  - `REGULAR_GAME_DAO_SHARE = 10`
- Ticket-game pool funding is separate through `computeTicketGamePoolCredit()` and explicit game raw/backed ticket pools.
- NFT listing fee is 2 Tokens and logs `nft-list`, but no clear hardened NFT-to-DAO credit path was found in canonical backend source.
- `index.html` still contains broad/misleading DAO revenue language:
  - `50% burned · 50% to DAO` for NFT mint confirmations.
  - game removal copy sends remaining ticket pool `50% burned · 50% to DAO treasury`.
  - manifesto copy says nearly half of revenue goes to DAO members.
  - DAO weekly draw copy says Tokens/Tickets are auto-deposited to DAO members without clarifying funding source.
  - creator copy says `5% DAO` / `10% DAO` but does not distinguish DAO gaming rewards from NFT/ticket revenue.

## Final Product Policy

- DAO revenue/rewards are funded only by gaming activity.
- Game ticket pools fund game/player prize payouts only.
- DAO member ticket jackpot, if kept, is funded only from DAO gaming rewards.
- NFT listing, NFT mint, NFT showroom, gashapon, artist/seller revenue, and token purchases do not fund DAO rewards unless explicitly re-approved later.
- Do not drain per-game ticket pools for DAO member rewards.

## Phase 1: [IAMJ] Frontend Copy Alignment

**Files:**
- Modify: `index.html`

**Steps:**
1. Replace NFT mint confirmation copy:
   - From: `50% burned · 50% to DAO`
   - To: copy that does not imply DAO funding, e.g. `Minting fee supports arcade operations and burn mechanics`.
2. Replace game removal copy:
   - From: remaining ticket pool split `50% burned · 50% to DAO treasury`
   - To: a non-DAO or governance-neutral statement, e.g. `If your game is removed, remaining ticket-pool handling follows the arcade removal policy and will not fund DAO member jackpots.`
3. Replace manifesto copy:
   - From: `nearly half our Revenue goes to our DAO Members`
   - To: `DAO member rewards are funded from gaming activity, while creator and NFT commerce remain separate.`
4. Clarify weekly DAO draw copy:
   - From: `Tokens/Tickets are auto deposited to randomized DAO Members`
   - To: `DAO gaming rewards may fund periodic member ticket jackpots; game ticket pools remain separate.`
5. Replace generic `community kickbacks` language with gaming-rewards wording.
6. Keep `DAO Favourites` as a curation label if present; do not remove curation/governance language unless it implies revenue sharing.

**Success criteria:**
- No frontend copy claims NFT/listing/mint/gashapon revenue goes to DAO.
- Frontend distinguishes game ticket pools from DAO gaming rewards/jackpots.
- Gameplay DAO share copy remains but is labeled as DAO gaming rewards, not broad DAO revenue.

## Phase 2: [IAMJ] Backend/IDL Surface Audit And Minimal Alignment

**Files:**
- Inspect/modify if needed: `backend/main.mo`
- Inspect/modify if needed: `index.html` Candid/IDL definitions

**Steps:**
1. Search for actual DAO credit/write paths related to NFT/gashapon/listing/mint/showroom/token purchases.
2. If no actual path exists, do not invent backend storage in this pass; only update comments/API-facing copy if misleading.
3. Keep gameplay split constants intact unless a real DAO ticket-revenue path exists outside gaming.
4. If `getRevenueSplitConfig` is frontend-only/stale and includes `userMintDaoShare`, `collectionDaoShare`, or similar, either remove usage from UI or relabel so it cannot present NFT DAO revenue as active final-product economics.
5. Do not change deploy targets or canister settings.

**Success criteria:**
- Backend source does not suggest NFT/gashapon/listing revenue funds DAO rewards.
- Any frontend IDL/dashboard wording is aligned to gaming-only DAO rewards.
- Gameplay split constants still compile.

**Phase 2 local result (2026-04-29):**
- Canonical backend audit found platform-wide NFT/listing/mint/showroom/token-purchase revenue logging, but no DAO reward credit path for those non-gaming sources.
- Gameplay DAO share constants remain intact; per-game ticket pools remain separate from DAO rewards.
- The frontend IDL preserves stale `getRevenueSplitConfig` compatibility fields, but comments mark them legacy and active DAO dashboard/treasury source rendering is filtered through a centralized gaming-only allowlist.
- No deploy was performed; Gmai review is still required before any acceptance/deploy decision.

## Phase 3: [IAMJ] Documentation Update

**Files:**
- Modify: `docs/plans/2026-04-29-dao-revenue-change-notes.md`
- Create/modify evidence note if useful under `docs/plans/`

**Steps:**
1. Mark Jay's decision as confirmed: DAO keeps gameplay revenue share; remove DAO from NFT/ticket/gashapon revenue.
2. Add final product policy language from this plan.
3. Note that implementation is copy/accounting alignment, not deploy authorization.

**Success criteria:**
- Docs show the final policy and stop condition clearly.

## Phase 4: [IAMJ] Verification

**Commands:**
- `rg -n "50% burned|50% to DAO|nearly half.*Revenue|community kickbacks|userMintDaoShare|collectionDaoShare|gashapon.*DAO|NFT.*DAO|DAO.*NFT" index.html backend/main.mo docs/plans/2026-04-29-dao-revenue-change-notes.md -S`
- Run the smallest available frontend/build validation for this project. If the project has no full test suite, at minimum run the frontend publish/build script in dry mode if safe: `node scripts/build-frontend-publish.mjs`.
- Run Motoko check/build only if backend source changed.

**Success criteria:**
- Search no longer finds stale DAO-from-NFT revenue promises, except historical docs clearly marked as old/evidence.
- Frontend build/publish package generation succeeds if run.
- Motoko check/build succeeds if backend changed.

## Phase 5: [GMAI] Review

**Scope:**
- Verify final product policy is correctly reflected in UI copy and any touched backend/API surface.
- Verify game ticket pools remain separate from DAO rewards.
- Verify NFT/gashapon/listing revenue no longer appears to fund DAO member rewards.
- Verify no deploy happened without explicit deploy approval.

**Success criteria:**
- Gmai verdict is `APPROVE`, `REVISE REQUIRED`, or `BLOCKED` with evidence.

## Phase 6: [JMAI] Delivery / Deploy Gate

**Steps:**
1. Report implementation commit and review verdict to Jay.
2. If approved and Jay explicitly authorizes deploy, perform ICP deploy preflight and deploy via canonical rule:
   - Build sanitized frontend payload with `node scripts/build-frontend-publish.mjs`.
   - Deploy only `.deploy/frontend-public`.
   - Target frontend canister `mprew-viaaa-aaaah-quola-cai`.
   - Backend target remains `pifyq-raaaa-aaaab-agrqq-cai` only if backend changed and deploy is explicitly authorized.

**Success criteria:**
- No live deploy is performed without explicit deploy approval.
