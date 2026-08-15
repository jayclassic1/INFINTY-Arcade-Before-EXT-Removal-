# INFINITY Arcade — AI Catch-Up Scope Document

Prepared for: Jay Nolan  
Prepared by: Jmai  
Date: 2026-06-23  
Project ID used in local docs: `ICP-ARCADE`

> Important grounding note: this document is compiled from the current local Infinity Arcade project files and runbooks in `dapps/infinity-arcade-Jay`. The OpenClaw project-truth wrapper did not resolve `ICP-ARCADE`/`arcade`, so a new AI should treat this document as a strong local handoff, but still re-check live canister state before any deployment or upgrade claim.

---

## 1. One-line product concept

**INFINITY Arcade is an ICP-hosted arcade platform where players connect a wallet, buy internal arcade Tokens, spend Tokens to play browser games, earn closed-loop Tickets, and redeem Tickets for NFT prizes and arcade perks.**

It is a product and game platform, not a token protocol.

Core philosophy:

- **Tokens** are internal arcade credits.
- **Tickets** are closed-loop prize/perk/governance points.
- Tickets are not direct ICP cashout instruments.
- Creator/seller earnings are ICP-denominated claimable balances, tracked separately from player arcade credits.
- Jay keeps final admin control. DAO/community features are intended as fun governance and rewards, not loss of founder/admin control.

---

## 2. Current canonical project truth

Use this active root for all normal work:

```text
C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay
```

Current production identifiers from local canonical docs:

```text
Frontend asset canister: mprew-viaaa-aaaah-quola-cai
Backend canister:        pifyq-raaaa-aaaab-agrqq-cai
Public URL:              https://mprew-viaaa-aaaah-quola-cai.icp0.io
```

Legacy/reference-only identifiers:

```text
Legacy frontend fallback: ewgfh-vqaaa-aaaah-qtixa-cai
Legacy backend/reference: sympv-naaaa-aaaad-qktuq-cai
Legacy local paths:       dapps/infinity-arcade, dapps/icp-arcade, icp-arcade
```

Critical rule:

**Do not deploy from or mutate legacy paths/canisters unless Jay explicitly asks for fallback/rollback work.**

The fresh-start migration into `infinity-arcade-Jay` was completed on 2026-04-25. A human wallet pass was marked good on 2026-04-25.

---

## 3. What the new AI should understand first

INFINITY Arcade has three separate layers that must not be confused:

1. **Frontend product shell**
   - Main file: `index.html`
   - Runs the public app UI, wallet flows, arcade browsing, prize booth, admin panels, creator dashboard, embedded game launch, legal pages, etc.

2. **Backend Motoko canister**
   - Main file: `backend/main.mo`
   - Owns internal balances, game submissions, NFT listings, ticket accounting, creator earnings, escrow records, leaderboards, forums, DAO/proposal state, and administrative functions.

3. **Deploy/publish payload**
   - Generated folder: `.deploy/frontend-public/`
   - This is the sanitized frontend payload. **Do not deploy the project root directly.**

Normal frontend publish preparation is:

```powershell
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

The actual live upload/deploy requires separate approval. A build-ready frontend payload is not the same thing as permission to publish.

---

## 4. Product areas and user roles

### Player

Players can:

- connect a wallet
- see ICP balance and arcade balances
- deposit ICP / receive internal Tokens
- spend Tokens to open game sessions
- play ticket games or regular games
- submit scores
- earn Tickets when rules allow
- browse Prize Booth/NFT listings
- redeem Tickets for prizes where supported
- view collection/owned items where collection scan paths work
- participate in forums/proposals where enabled

### Game creator / developer

Creators can:

- submit games to The Back or Showroom/on-chain review
- provide playable URLs or zip-ready static games
- earn creator shares from certain paid gameplay flows
- potentially receive tips in planned/partially implemented Backroom tipping flows
- appear in creator dashboards/earnings dashboards

### NFT creator/seller

NFT participants can:

- list existing NFTs
- list/mint platform NFTs
- apply for Showroom placement
- confirm escrow for EXT, DIP-721, or ICRC-7 style NFTs
- redeem/list/remove depending on status and admin rules

Current caution: ticket-based NFT redemption intentionally does not automatically mean the seller gets ICP. NFT seller payout lanes are separate and must be explicitly designed/funded.

### Admin / Jay

Admin has final control over:

- approving/rejecting games
- approving/rejecting NFT showroom listings
- promoting Jay's Picks
- ticket/cost settings
- some collection/mint/ability tools
- treasury/withdrawal functions where backend support and safety gates exist
- moderation/forum tools
- future DAO/jackpot controls

Admin UI must be honest about backend capability. If the backend method is not exposed, the UI should show a disabled/capability-guarded state, not a scary red error.

---

## 5. Current economy model

### Token rate

Current backend notes say:

```text
0.01 ICP = 1 Token
1 ICP = 100 Tokens
```

### Ticket liability baseline

Current backend constants indicate:

```text
1 ICP = 1,000 Tickets
1 Ticket = 100,000 e8s
```

Tickets are internal closed-loop balances and should not be presented as directly cashout-able.

### Ticket games — intended split

Jay's clarified intended split for paid ticket games:

```text
20%  game creator
5%   DAO gaming rewards
5%   burn
70%  game ticket balance / ticket pool
```

Meaning: ticket games are not pure creator-revenue games. Most value funds that game's ticket payout pool.

### Regular / non-ticket games — intended split

For paid regular games that do not pay Tickets:

```text
80%  game creator
10%  DAO gaming rewards
10%  burn
```

Meaning: regular games are creator-heavy because there is no ticket pool liability.

### NFT sales

Current backend notes preserve:

```text
90% NFT creator/seller
10% operating treasury/platform
```

But the exact seller payout lane must be treated carefully. Ticket-based redemption is not the same as an ICP seller payout unless a funded payout model is explicitly implemented.

### Public truth rule

Public UI must show only economically truthful values.

Current direction:

- public ticket pool = **backed-only** ticket pool
- raw/internal counters = admin diagnostic only

Do not display raw/unbacked exposure to players as if it is funded prize value.

---

## 6. Session pricing policy

A creator/admin-set Token price opens **one live session**.

Important rules:

- `X Tokens = one live session`
- the price is not per death
- the price is not per retry
- the price is not per single run
- once a session is opened, the player may die/retry repeatedly
- player ends the session manually with something like `Submit Score & Close` or `Force Close`
- score submitted is the latest run score

Preferred copy:

- `1 Token opens a live session`
- `3 Tokens open a live session`
- `Session Price`

Avoid:

- `per life`
- `per death`
- `insert another token after every run`

---

## 7. Current backend capability surface

Main backend source:

```text
backend/main.mo
```

Major backend systems present:

1. **Tokens**
   - `deposit`
   - `creditTokens`
   - `spendTokens`
   - `spendTokensOnGame`
   - `convertDepositToTokens`
   - `getTokens`
   - `getAllTokens`

2. **Tickets**
   - `getTickets`
   - `addTickets`
   - `adminSetTickets`
   - `batchAddTickets`
   - `awardTickets`
   - `winTickets`
   - `getAllTickets`

3. **Paid game sessions / score submission**
   - `submitGameScore`
   - `endGameSession`
   - `getPlayerGameStats`
   - cooldowns, daily caps, play stats, trial stats

4. **Leaderboards**
   - `submitHighScore`
   - `getHighScore`
   - `getAllHighScores`

5. **Game submissions**
   - `submitGame`
   - `adminAddGame`
   - `adminGetAllGames`
   - `applyGameShowroom`
   - `approveGameShowroom`
   - `rejectGameShowroom`
   - `promoteGameToJaysPicks`
   - `removeGameSubmission`
   - `getGameSubmissions`
   - `getGamesByTier`

6. **Ticket pools / jackpot accounting**
   - `getGameRawTicketPool`
   - `getGameBackedTicketPool`
   - `getAllGameRawTicketPools`
   - `getAllGameBackedTicketPools`
   - `getTicketReserveAudit`
   - `setGameTicketJackpotConfig`
   - `getGameTicketJackpotConfig`
   - `getRecentTicketJackpotWins`
   - `getRecentTicketJackpotWinDetails`
   - `getGameTicketJackpotSnapshot`

7. **NFT / Prize Booth / escrow**
   - `listExistingNft`
   - `listExistingNftWithTokenKey`
   - `listMintedNft`
   - `applyNftShowroom`
   - `approveNftShowroom`
   - `rejectNftShowroom`
   - `promoteNftToJaysPicks`
   - `removeNftListing`
   - `getNftListings`
   - `getNftListing`
   - `getMyNftListings`
   - `confirmExtEscrow`
   - `confirmDip721Escrow`
   - `confirmIcrc7Escrow`
   - `redeemUserNft`
   - `returnEscrowNft`
   - `getEscrowStatus`
   - `getAllEscrows`

8. **Creator earnings / refunds / seller earnings**
   - `getRoyalties` legacy-compatible name
   - `getGameCreatorEarnings`
   - `getNftSellerEarnings`
   - `getClaimableEarningsBreakdown`
   - `creditRoyalty`
   - `claimRoyalties`
   - debit-before-ledger-await with restore on error/trap is important safety behavior

9. **Treasury / withdrawals**
   - `getTreasuryBalance`
   - `getTreasuryLaneSnapshot`
   - `adminWithdrawOperatingTreasury`
   - `adminWithdrawOperatingTreasuryToAccountId`
   - `adminWithdrawTreasury`
   - `withdrawDeposit`
   - `withdrawDepositToAccount`

10. **Forums / DAO / governance-style features**
   - `getForumThreads`
   - `createForumThread`
   - `addForumReply`
   - `createProposal`
   - `castVote`
   - `addProposalReply`
   - `getProposals`
   - `getProposal`
   - `daoStats`
   - gamer badge functions

11. **ICP tipping for The Back — recently prepared/partially implemented surface**
   - `recordIcpTip`
   - `getGameIcpTipSummary`
   - `getRecentGameIcpTips`

Current tipping architecture in docs: non-custodial direct ICP transfer from user wallet to creator, then backend records display/audit receipt after successful transfer. Backend receipt is not custody and not payout accounting.

---

## 8. Current frontend systems

Main frontend file:

```text
index.html
```

High-level UI/features present or documented:

- landing / arcade hub
- wallet connect/disconnect
- ICP balance chip and wallet panel
- deposit/withdraw flows
- Token and Ticket balance display
- Arcade Hall / game browsing
- The Back / Backroom creator game area
- Showroom / game listings
- Prize Booth / NFT listings
- My Collection button and collection scan flows
- admin panels for moderation, submissions, ticket/game/prize controls, treasury, and diagnostics
- creator/developer dashboard
- creator earnings/royalty dashboard
- manifesto/legal/privacy/terms content
- embedded game runtime support under `games/`
- universal Start overlay for games
- forum/proposal/community surfaces

Important caveat:

Some admin panels historically called backend methods not installed on `pifyq`. Fixes should capability-guard unsupported panels instead of throwing red errors.

---

## 9. Current games/assets

Canonical `games/` currently includes at least:

```text
games/infection
games/skate-apocalypse
games/swing-blade
```

Public media/assets include arcade/prize/gashapon/showroom/manual backgrounds, legal docs, and deployable game runtime assets.

Game submission requirements:

- must run in browser
- must run inside iframe
- Chromium and Firefox support required
- mobile/tablet only if marked mobile-compatible
- thumbnail/image uploads max 2 MB
- Showroom/on-chain zip max 10 MB
- every uncompressed file inside zip max 2 MB
- zip must include `index.html`
- all assets bundled locally for Showroom/on-chain mode
- no CDN scripts, remote images/audio, external APIs, server-only logic, or runtime package installs
- no backend/wallet/canister calls inside the game loop
- score must be a positive integer where higher is better
- support both native keyboard input and Arcade parent `postMessage` input

Arcade parent input contract:

```js
{
  type: 'arcade-key',
  player: 0,
  action: 'left' | 'right' | 'up' | 'down' | 'a' | 'b' | 'c' | 'd' | 'start',
  state: 'down' | 'up'
}
```

Games should treat `a` and/or `start` as Start/Confirm so the platform-level Start overlay can activate the game.

---

## 10. Deploy and upgrade path rules

### Frontend deploy path

Frontend deploy preparation:

```powershell
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Deploy source:

```text
.deploy/frontend-public/
```

Never deploy:

```text
project root directly
legacy dapps/infinity-arcade
legacy dapps/icp-arcade
legacy icp-arcade
```

### Backend build path

Backend safe local build/check commands from `package.json` include:

```powershell
npm run backend:build
npm run backend:check
npm run backend:mops:check
```

### Backend upgrade readiness packet

There is a project-local readiness manager:

```powershell
node scripts/prepare-infinity-arcade-upgrade.mjs --artifactDir=C:\Users\Jesse\OpenClawEvidence\icp-arcade-icp-tipping
```

Compatibility wrapper:

```powershell
node scripts/prepare-jay-backend-upgrade-lane.mjs --artifactDir=C:\Users\Jesse\OpenClawEvidence\icp-arcade-icp-tipping
```

This manager is readiness-only. It does **not** deploy, upgrade, upload frontend assets, create canisters, touch controllers/cycles/identity/secrets, restart the gateway, or run raw local-network commands.

It reads fresh build artifacts only from:

```text
backend/.build/arcade_backend.wasm
backend/.build/arcade_backend.did
```

It intentionally does not use stale `.dfx` artifacts as candidate inputs.

Before any live backend upgrade, a separate governed safe-wrapper proof and explicit approval are required. The current readiness manager has `mutationAllowedNow: false`.

---

## 11. Known issues and next work

### 1. Deploy path / project truth mismatch

Local docs clearly identify `infinity-arcade-Jay`, `mprew`, and `pifyq` as active. However, OpenClaw's `jmai_project_truth` tool did not resolve `ICP-ARCADE` or `arcade` during this handoff.

This means the next AI should not assume deploy automation is clean just because code exists. Before live action, fix or route around the project-truth binding problem and verify the real live canisters.

### 2. Backend live mutation lane is readiness-only

The backend upgrade manager can produce packets and verify candidate artifacts, but it does not itself execute live backend upgrades. A separate governed lane/provider proof is required.

### 3. Admin panel capability drift

Some frontend panels may still reference backend methods not exposed on `pifyq`. Preferred fix: capability guards, disabled copy, and soft-fail UX.

### 4. DAO jackpot/dashboard incomplete

DAO rewards/jackpots are directionally aligned but not functionally complete. Intended rule: DAO rewards are game-earned only.

Future path:

1. persist DAO gaming reward balances separately from platform-wide revenue logs
2. credit DAO rewards only from paid gameplay splits
3. add backend dashboard/treasury/source breakdown/history APIs
4. add admin/DAO draw mechanics
5. add winner notification/claim path
6. keep non-game revenue excluded unless Jay changes rule

Jay's future direction includes a 7-week round robin with at least two ICP-backed reward lanes:

- DAO member Token redistribution
- Backroom Tip Credits that can only be used to tip The Back creators

### 5. Backroom creator tipping

Current plan favors direct ICP tips from player wallet to creator principal, with backend display receipts after transfer. Token tips / Tip Credits are future design work and must preserve closed-loop Token rules.

### 6. NFT seller payout lane

Ticket redemption should not be treated as seller ICP income unless a funded seller payout lane is explicitly implemented.

### 7. Legacy retirement not approved

Do not delete legacy roots/canisters. Retirement needs validation window, snapshots/backups, asset inventory, rollback plan, and explicit approval.

---

## 12. Validation commands worth knowing

Useful commands documented in the project:

```powershell
node scripts/test-frontend-publish.mjs
node scripts/build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
npm run backend:build
node scripts/validate-real-icp-api-surface.mjs
node scripts/validate-dao-jackpot-funding-rule.mjs
node scripts/test-infinity-arcade-upgrade-manager.mjs
node scripts/test-jay-backend-upgrade-lane.mjs
node scripts/test-icp-tip-ui-contract.mjs
node scripts/validate-mobile-wallet-access.mjs
node scripts/validate-auth-client-7day-session.mjs
```

Other validators exist for treasury safety, jackpot tiers, creator earnings, wallet chips, My Collection, ticket pool visibility, and frontend deploy artifact sync.

A new AI should inspect `package.json`, `scripts/`, and recent `docs/runbooks/` before choosing validation gates.

---

## 13. How to work safely with a new AI/Claude

If using Claude or another AI to build, give it this rule set:

1. Work only in:

```text
C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay
```

2. Treat these as active targets:

```text
Frontend: mprew-viaaa-aaaah-quola-cai
Backend:  pifyq-raaaa-aaaab-agrqq-cai
```

3. Do not deploy or upgrade anything unless Jay explicitly approves that exact live action.

4. Do not use legacy paths/canisters except for rollback/reference analysis.

5. Frontend changes should update `index.html` and then regenerate `.deploy/frontend-public/` with the build script.

6. Backend changes must preserve stable-state compatibility in `backend/main.mo`.

7. Backend upgrades require:

- local build
- DID/WASM hash capture
- state/snapshot/rollback plan
- Gmai/review gate
- explicit live approval
- governed safe-wrapper/proven deploy lane
- post-upgrade verification

8. Never confuse:

- Tokens with ICP
- Tickets with withdrawable cash
- raw ticket pool with backed ticket pool
- creator earnings with player credits
- NFT redemption with seller payout
- readiness packet with live deploy

9. Use tests/validators before claiming success.

10. If a tool or canister state cannot be verified live, say so plainly.

---

## 14. Recommended immediate roadmap

### Now

- Fix project-truth/binding visibility so OpenClaw resolves `ICP-ARCADE` cleanly.
- Re-check live frontend/backend state before any new deploy claim.
- Continue building from `infinity-arcade-Jay` only.

### Next

- Clean up admin capability guards for methods not exposed on `pifyq`.
- Finish/verify ICP tipping UX and backend receipt path if not already deployed.
- Decide whether the next live change is frontend-only, backend-only, or paired.

### Later

- Complete DAO jackpot / 7-week round robin reward architecture.
- Implement Tip Credits if Jay wants that economy lane.
- Formalize NFT seller payout economics.
- Retire legacy canisters/paths only after stabilization and explicit approval.

---

## 15. Copy/paste starter prompt for a new AI

Use this with Claude or another builder:

```text
You are helping build INFINITY Arcade, Jay Nolan's ICP-hosted arcade platform.

Canonical root:
C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay

Active production canisters:
Frontend: mprew-viaaa-aaaah-quola-cai
Backend: pifyq-raaaa-aaaab-agrqq-cai
Public URL: https://mprew-viaaa-aaaah-quola-cai.icp0.io

Do not use legacy roots/canisters except as reference/fallback:
- dapps/infinity-arcade
- dapps/icp-arcade
- icp-arcade
- ewgfh-vqaaa-aaaah-qtixa-cai
- sympv-naaaa-aaaad-qktuq-cai

Product model:
Players buy internal Tokens with ICP, spend Tokens to play browser games, earn closed-loop Tickets, and redeem Tickets for prizes/perks/NFTs. Tokens and Tickets are internal arcade balances, not DEX assets. Tickets are not direct ICP cashout instruments. Creator/seller earnings are separate ICP-denominated claimable balances.

Important economy:
Ticket games: 20% creator / 5% DAO / 5% burn / 70% ticket pool.
Regular games: 80% creator / 10% DAO / 10% burn.
NFT sales: intended 90% seller/creator / 10% operating treasury, but seller payout lane must be explicitly funded and safe.

Frontend:
Main file is index.html. Deploy payload is generated into .deploy/frontend-public/. Never deploy the project root directly.
Build/check:
node scripts\build-frontend-publish.mjs
scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai

Backend:
Main file is backend/main.mo. Use npm run backend:build and project validators. Preserve stable-state compatibility. Backend live upgrades require explicit approval, rollback/snapshot plan, governed safe-wrapper proof, and post-verification.

Do not deploy, upgrade, create canisters, change controllers/cycles/identity, or run live mutation commands unless Jay explicitly authorizes that exact action.

Before making changes, inspect PROJECT.md, PROJECT_OVERVIEW.md, CANONICAL.md, PROJECT_ROOT_STRUCTURE.md, README_CANONICAL_DEPLOY.md, SESSION_PRICING_POLICY.md, BLACKHOLE_OPTIMIZATION_POLICY.md, and recent docs/runbooks.
```

---

## 16. Bottom line on deploy path problems

A Claude subscription or new AI can help write and reason about the code faster, but it does **not** by itself solve deploy path problems.

The remaining deploy-path risk is not model intelligence. It is operational truth and authority:

- exact canonical root must be bound
- exact frontend/backend canisters must be verified
- sanitized frontend payload must be used
- backend live mutation lane must have governed execution proof
- rollback/snapshot/post-verify gates must exist
- legacy canisters/paths must not be accidentally used

Once those are clean, a new AI can be very useful. Until then, it should build and prepare packets, not claim live deployment success.
