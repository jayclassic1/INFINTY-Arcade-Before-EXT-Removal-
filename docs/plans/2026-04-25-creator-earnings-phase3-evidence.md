# Creator Earnings Phase 3 Evidence — Economy Unit Cleanup

Date: 2026-04-25
Task: `icp-arcade-creator-earnings-phase3-unit-cleanup-20260425`
Project: ICP-ARCADE / Infinity Arcade (Jay Nolan)
Target canister: `pifyq-raaaa-aaaab-agrqq-cai`
Deploy authorized: no

## Scope

Phase 3 focused on creator/seller earnings and royalty unit safety:

- Creator earnings / royalties must store ICP e8s only.
- Refunds must not share the creator earnings / royalties bucket.
- Ticket-paid NFT redemptions must not invent a ticket-to-ICP conversion.
- Product copy must preserve the closed-loop distinction:
  - Tokens are arcade credits.
  - Tickets are prize/perk points and cannot be exchanged for ICP.

## Audit Summary

Audited backend royalty writes and relevant frontend copy. Pre-change risk areas were:

- Application/removal refund paths credited `royalties` directly.
- Ticket-based NFT redemption credited seller/creator royalties using ticket cost as if it were ICP.
- Frontend rejection copy described refunds as creator earnings.
- Phase 2 validation assumed a single claim bucket and needed alignment after refund separation.

## Changed Files

- `backend/main.mo`
  - Added separate stable/runtime refund balance storage: `refundEntries` / `refundsE8s`.
  - Added `getRefundBalance`, `creditRefundE8s`, and `restoreRefundBalance` helpers.
  - Moved NFT/game showroom rejection and game-removal refunds out of `royalties` into refund balances.
  - Updated `claimRoyalties` to claim creator ICP earnings plus separated ICP refunds atomically, debit both before ledger await, and restore both independently on ledger `#Err` or transfer trap.
  - Removed ticket-cost-to-ICP royalty credit from `redeemUserNft`; seller ICP payout for ticket redemptions is deferred because no explicit funded ICP source exists yet.
  - Updated comments to state royalties are ICP e8s only and refunds are separate.
- `index.html`
  - Updated admin rejection alerts to say refunds are credited to a separate ICP refund balance, not creator earnings.
- `scripts/validate-creator-earnings-phase2.mjs`
  - Updated claim-restore assertions for separated `earningsBalance` and `refundBalance` semantics.
  - Keeps coverage that locked funds are restored and interim credits are preserved through additive restore helpers.
- `scripts/validate-creator-earnings-phase3.mjs`
  - Added Phase 3 unit-safety validation for royalty writes, refund separation, ticket redemption, and product copy.
- `docs/plans/2026-04-25-creator-earnings-phase3-evidence.md`
  - This evidence record.

## Checks Run

- `node scripts\validate-creator-earnings-phase2.mjs`
  - PASS: 11/11
- `node scripts\validate-creator-earnings-phase3.mjs`
  - PASS: 8/8
- `icp_check_motoko` on `backend`
  - PASS: 0 errors
  - Warnings: 32 existing compiler warnings surfaced by Motoko check (redundant `stable`, existing unused identifiers, and possible Nat traps). No Motoko errors.

## Residual Risks

- Ticket-based NFT redemption now avoids unsafe ICP accounting, but seller ICP payout for ticket redemptions remains deferred until a funded source-of-truth design exists.
- Refund balances are included in the existing `claimRoyalties` transfer path for scoped compatibility; UI/API naming still says `claimRoyalties`, so a future UX cleanup should expose clearer wording such as “claim creator earnings/refunds”.
- Motoko warnings remain outside this Phase 3 scope.

## Recommended Next Step

Design and implement an explicit ticket-redemption seller-credit model only after the ticket backing/funding source is defined. Do not add a ticket-to-ICP conversion formula until that source and policy are approved.
