# Future Build Notes — 2026-05-14

## DAO jackpot / DAO rewards

Soft-audit finding: DAO jackpot concept is directionally aligned, but current live build is not functionally complete.

Intended system:
- DAO rewards/jackpots are game-earned only.
- Funding sources are qualifying paid gameplay only.
- Ticket games route 5% to DAO gaming rewards.
- Regular/non-ticket games route 10% to DAO gaming rewards.
- NFT mints/listings/showroom fees, gashapon, deposits, creator/seller payouts, refunds, withdrawals, treasury sweeps, and non-game platform fees must not fund or be described as funding DAO jackpots/rewards unless Jay explicitly changes the rule.

Current alignment:
- Backend constants/copy/validator support the game-earned-only rule.
- `scripts/validate-dao-jackpot-funding-rule.mjs` passes.
- Frontend allowlists only gaming reward source labels.
- Live backend is missing several DAO dashboard/jackpot methods currently referenced by frontend, including `getDaoDashboard`, `getDaoRevenueBreakdown`, `getLotteryHistory`, `getDaoTreasuryFull`, and `daoStats`.

Future build path:
1. Persist DAO gaming reward balances separately from platform-wide revenue logs.
2. Credit DAO rewards only from paid gameplay splits.
3. Add backend read APIs for dashboard/treasury/source breakdown/history.
4. Add controlled admin/DAO draw mechanics.
5. Add winner notification/claim path.
6. Keep non-game revenue excluded and keep validator updated with any product-rule change.

Jay follow-up product direction — credit conversion + 7-week round robin:
- Jay wants the DAO jackpot system to work with the planned 7-week round robin system.
- DAO jackpot should split into at least two ICP-backed reward lanes:
  1. DAO member Token redistribution: ICP-backed arcade Tokens distributed to DAO members, still closed-loop and not directly withdrawable by players.
  2. Backroom Tip Credits: ICP-backed credits awarded to DAO members/players that can only be used to tip The Back creators.
- Tip Credits should convert to creator claimable ICP only when actually sent as a tip to a creator.
- Players/DAO members should not be able to cash out Tip Credits directly; only creators receive real income after a tip event.
- The 7-week round robin can choose or rotate recipient groups/games/members, while the payout accounting keeps Token redistribution and Tip Credit conversion separate.

Status: notes only; no implementation started.

## Backroom creator tipping

Soft-audit finding: The product idea is a strong fit, and the frontend already has partial/stale UI concepts for Backroom tips, but the live backend does not currently implement the tipping API.

Intended system:
- Users can tip The Back game creators.
- Tips can be arcade Tokens, ICP, Backroom Tip Credits, or a phased subset.
- Creator can later cash out claimable ICP for real income.
- Token tips should become ICP-denominated creator earnings only if the system has a real backing rule for those Tokens.
- Tip Credits are the preferred credit-conversion design: ICP-backed, non-withdrawable by players, only spendable as Backroom creator tips, and converted into creator claimable ICP at the moment of tipping.
- ICP tips should move actual ICP into the canister-controlled accounting path before crediting the creator.

Current alignment:
- Backroom game submissions store creator principal, so recipient routing is available.
- Creator/seller earnings claim flow already exists via `claimRoyalties()` and claimable ICP e8s buckets.
- Frontend has Backroom tip UI/buttons and an IDL entry for `tipBackroomCreator`, but backend `.did` and `backend/main.mo` do not expose/implement that method in the current build.
- ICP tip UI is explicitly deferred in frontend copy as "ICP Tip Coming Soon" because safe transfer routing is not wired.
- Current public copy says The Back has no creator revenue share; tipping would be a separate creator-support lane, not ordinary revenue share.

Risk/architecture notes:
- Do not make Tokens directly withdrawable by users; existing rule says Tokens are arcade credits only.
- If Token tips credit creator ICP, they must debit player Tokens and credit creator earnings at the canonical Token liability value, while preserving treasury backing math.
- ICP tips are cleaner economically but require a safe deposit/transfer confirmation path to prevent fake credits and double-spends.
- Tip accounting should be separate from gameplay revenue, DAO rewards, NFT seller earnings, and refunds, even if claims can use the same final payout pipe.
- Add tip event history for auditability: tipper, creator, gameId, source asset, amount, e8s credited, timestamp.

Suggested build path:
1. Phase A: Backend token-tip method for Backroom games only: authenticate caller, validate live Backroom game, reject self-tip if desired, debit Tokens, convert to e8s at canonical rate, credit a separate creator tip earnings bucket or creator earnings with source metadata.
2. Phase B: Frontend token-tip UI wired to real backend method, with accurate copy: "Token tips credit creator claimable ICP earnings, subject to backing and claim minimums."
3. Phase C: ICP-tip path using a dedicated creator-tip deposit/payment flow; verify ledger funds before crediting creator.
4. Phase D: Creator dashboard splits earnings by gameplay royalties, Backroom tips, NFT seller earnings, and refunds.
5. Phase E: Claim flow continues to pay ICP e8s after ledger-safe debit/restore checks.

Difficulty estimate:
- Token tips only: medium, roughly 1 focused backend/frontend pass plus Gmai review.
- ICP tips: medium-high, because ledger verification and payment UX must be safe.
- Full polished income product with history/dashboard/tax-safe copy: high enough to treat as a real feature phase, not a quick UI patch.

Status: notes only; no implementation started.
