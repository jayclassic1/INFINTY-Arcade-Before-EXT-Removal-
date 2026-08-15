# Project Overview - Infinity Arcade (Jay Nolan)

Last updated: 2026-04-25  
Purpose: condensed memory note for new Jmai/Iamj/Gmai sessions. Read this first before working on Infinity Arcade.

---

## One-line concept

Infinity Arcade is an ICP-hosted arcade where players buy internal **Tokens**, spend Tokens to play browser games, earn closed-loop **Tickets**, and redeem Tickets for NFT prizes in a prize booth. It is a product, not a token protocol.

Core philosophy:

- Tokens and Tickets are internal arcade balances, not DEX assets.
- Tickets are prize/perk/governance points, not ICP cashout instruments.
- Creator/seller earnings are ICP-denominated claimable balances, tracked separately from player arcade credits.
- Jay keeps final admin control; community/DAO features are intended as fun governance, not protocol control.

---

## Production truth

Project ID: `ICP-ARCADE`  
Project name: `Infinity Arcade (Jay Nolan)`  
Canonical active root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`

Active canisters:

- Frontend asset canister: `mprew-viaaa-aaaah-quola-cai`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Public URL: `https://mprew-viaaa-aaaah-quola-cai.icp0.io`

Legacy/reference only:

- Legacy frontend fallback: `ewgfh-vqaaa-aaaah-qtixa-cai`
- Legacy backend/reference: `sympv-naaaa-aaaad-qktuq-cai`
- Legacy local paths: `dapps/icp-arcade`, `icp-arcade`

Do not deploy from or mutate legacy paths/canisters unless Jay explicitly asks for fallback/rollback work.

---

## Deploy rule

Frontend deploys must use the sanitized payload only:

```powershell
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Deploy source must be:

```text
.deploy/frontend-public/
```

Never deploy the project root directly. The sanitized payload currently includes allowlisted public app files, public media/assets, legal docs, `dfinity-bundle.js`, and game runtime assets.

Backend mutations target `pifyq-raaaa-aaaab-agrqq-cai` only when backend work is explicitly authorized.

---

## Current intended economy - Jay directive 2026-04-25

Jay clarified the forward target economics:

### Ticket games

When a player spends Tokens on a ticket-paying game:

- **20%** to the game creator
- **5%** to DAO
- **5%** burned
- **70%** converts into that game's ticket balance / ticket pool

Meaning: Ticket games are not pure creator-revenue games. Most value funds the game's ticket payout pool.

### Regular / non-ticket games

There is a regular game category that does **not** pay Tickets. For those games:

- **80%** to the game creator
- **10%** to DAO
- **10%** burned

Meaning: non-ticket games are creator-heavy because there is no ticket-pool liability.

### Important current drift

The live backend currently still reports:

- `gameCreatorShare = 75`
- `nftCreatorShare = 90`

and `spendTokensOnGame()` currently credits creator royalties using the old 75% game-creator model. That is **not aligned** with Jay's newly confirmed target split above.

Treat this as the next economy reconciliation target, not as finished truth.

---

## Key frontend systems

Main file: `index.html`.

High-level UI/features present:

- Landing / arcade hub with ICP Arcade visual theme.
- Wallet connect/disconnect.
- ICP balance chip, wallet panel, deposit/withdraw flows.
- Internal Token and Ticket balances.
- Arcade Hall / game browsing.
- Prize Booth / NFT listings / collection tabs.
- My Collection button and collection scan flows.
- Admin panels for moderation, submissions, ticket/game/prize controls, and diagnostics.
- Creator / developer dashboard.
- Creator earnings / royalty dashboard.
- Manifesto / legal / privacy / terms content.
- Embedded game runtime support under `games/`.

Important frontend caveat:

- Some admin panels still call legacy/future backend methods that `pifyq` does not currently expose, which creates red IC `Method not found` errors. These should be capability-guarded as "backend slice not installed" instead of shown as scary red failures.

---

## Backend systems in place

Main backend source: `backend/main.mo`.  
Current built interface: `backend/.build/arcade_backend/arcade_backend.did`.

Major backend areas:

1. **Token balances**
   - `deposit(icpE8s, blockIndex)` credits internal Tokens after ICP deposit verification input.
   - Current rate: 0.01 ICP = 1 Token, so 1 ICP = 100 Tokens.
   - `creditTokens`, `spendTokens`, `spendTokensOnGame` exist.

2. **Ticket balances**
   - Tickets are internal balances.
   - `getTickets`, `addTickets`, `adminSetTickets`, `batchAddTickets`, `awardTickets`, `winTickets` exist.
   - Tickets are closed-loop prize/perk/governance points.

3. **Anti-bot game framework**
   - Tracks play cooldowns, daily ticket caps, plays/hour, total plays, and trial plays.
   - `submitGameScore()` handles score submission, rate checks, and ticket payout logic.
   - `getPlayerGameStats()` exposes player stats.

4. **Leaderboards**
   - `submitHighScore`, `getHighScore`, and `getAllHighScores` exist.
   - Leaderboard entries track gameId, player, score, timestamp.

5. **NFT listings / Prize Booth**
   - `listExistingNft`, `listMintedNft`.
   - Showroom application/approval/rejection for NFTs.
   - Jay's Picks promotion for NFTs.
   - Listing removal and user listing queries.
   - Ticket redemption for user-listed NFTs via `redeemUserNft()`.

6. **Game submissions**
   - `submitGame`.
   - Apply/approve/reject/promote/remove game submissions.
   - Query by tier/status.

7. **Model A ticket accounting**
   - Raw ticket pools and backed ticket pools are tracked separately.
   - Queries include `getGameRawTicketPool`, `getGameBackedTicketPool`, `getAllGameRawTicketPools`, `getAllGameBackedTicketPools`, and `getTicketReserveAudit`.
   - Public ticket values should remain backed-only.

8. **Creator earnings / royalties**
   - `royalties` map stores ICP-e8s creator earnings.
   - `refundsE8s` map stores separate ICP refunds.
   - `getRoyalties`, `creditRoyalty`, `getRevenueSplits`, `claimRoyalties` exist.
   - Claim flow debits earnings/refunds before ledger await and restores on ledger error/trap.
   - Current name `claimRoyalties` is legacy-compatible; UI copy should say creator earnings/refunds.

9. **NFT escrow**
   - EXT, DIP-721, and ICRC-7 escrow confirmation paths exist.
   - `redeemUserNft()` transfers escrowed NFTs to buyers after Ticket spend.
   - Ticket-funded seller ICP payout is intentionally deferred; Tickets do not convert into ICP royalties.
   - `returnEscrowNft` supports admin return.

10. **Revenue and stats**
    - `logRevenue`, `getRevenueLog`, `getRevenueSummary`, `getTotalRevenue`, `stats`.

11. **Withdrawals**
    - `withdrawDeposit` and `withdrawDepositToAccount` move ICP from user subaccounts.
    - `claimRoyalties` sends claimable earnings/refunds from the canister main ICP ledger account into caller's derived subaccount, then normal withdraw can move it outward.

12. **Health**
    - `whoami` and `stats` exist.

---

## Current games/assets

Canonical `games/` directory currently includes:

- `infection`
- `skate-apocalypse`
- `swing-blade`

Public media/assets include arcade/prize/gashapon/showroom/manual backgrounds and public docs/legal files.

---

## Current validation scripts

Scripts in `scripts/` include:

- `build-frontend-publish.mjs` - builds sanitized public frontend payload.
- `predeploy-check.ps1` - verifies deploy target/source safety.
- `test-frontend-publish.mjs` - publish payload test.
- `test-model-a-chain.mjs` - Model A accounting chain test.
- `test-shred-gnar-local-entry.mjs` - game entry test.
- `test-ticket-pool-visibility.mjs` - backed ticket visibility test.
- `validate-ticket-pool-frontend.js` - frontend ticket pool validation.
- `validate-creator-earnings-phase1.mjs` through `phase4.mjs` - creator earnings/copy/safety validation.
- `validate-my-collection-buttons.mjs`.
- `validate-wallet-balance-chip.mjs`.
- `validate-wallet-globals.mjs`.

---

## Known issues / next important work

1. **Economy split mismatch**
   - Jay's intended split is now 20/5/5/70 for ticket games and 80/10/10 for regular games.
   - Backend still has the old 75% game-creator share constant and behavior.
   - Needs a backend/frontend reconciliation plan before claiming economy complete.

2. **Admin panel red errors**
   - Frontend calls some backend methods that do not exist on `pifyq`, e.g. ban management and external collection registry methods.
   - Fix should be capability guards / disabled-state UI unless backend implementation is explicitly requested.

3. **NFT seller payout lane deferred**
   - `NFT_CREATOR_SHARE = 90` exists, but ticket-based NFT redemption does not currently credit seller ICP.
   - This is intentional until a funded seller payout model exists.

4. **Treasury/admin lane visibility incomplete**
   - Detailed DAO/burn/lane balances are not exposed by backend yet.
   - Current lane dashboards should be treated as display-only or future-slice until backend support lands.

5. **Legacy retirement not approved**
   - Keep legacy canisters and trees as reference/fallback only.
   - Retirement requires a clean validation window, snapshots/backups, asset inventory, rollback plan, and explicit approval.

---

## Source-of-truth rules for future sessions

- Use this project root: `dapps/infinity-arcade-Jay`.
- Do not mix in legacy arcade trees unless explicitly doing archival recovery.
- Do not deploy root; deploy `.deploy/frontend-public` only.
- Treat `mprew` frontend and `pifyq` backend as active production.
- Build authorization is not deploy authorization.
- Backend/canister mutations require explicit approval and preflight.
- For small aesthetic/frontend-only copy tweaks, Gmai can be bypassed with an explicit low-risk bypass note, but code/config/backend/deploy/economy changes still require review.

---

## Quick current status

- Fresh-start migration completed 2026-04-25.
- Wallet pass was good 2026-04-25.
- ICP balance chip opens wallet panel; refresh remains independent.
- My Collection button/scan behavior has recent validation coverage.
- Creator earnings safety validators pass, but economics need update to Jay's newly clarified splits.
