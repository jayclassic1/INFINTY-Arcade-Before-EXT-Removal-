# Infinity Arcade Creator Earnings Pivot — Phased Plan

Date: 2026-04-25
Project: ICP-ARCADE / Infinity Arcade
Active path: frontend `mprew-viaaa-aaaah-quola-cai`, backend `pifyq-raaaa-aaaab-agrqq-cai`
Canonical root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`

## Decision

Pivot away from automatic timed royalty payouts and toward claimable creator earnings.

Canonical product rule:

> Creator/seller earnings accrue in an ICP-denominated claimable balance. Creators manually claim when they want. Tokens remain arcade credits. Tickets remain prize/perk points and cannot be exchanged for ICP.

## Non-goals

- No weekly automatic batch payout in this pass.
- No Tickets -> ICP cash-out.
- No creator revenue paid as withdrawable arcade Tokens.
- No DEX/listed token behavior.
- No deploy without Gmai review and explicit deploy approval.

## Phase 1 — Source-of-truth alignment and safety baseline

Owner: Iamj implementation, Jmai verification, Gmai review.

Goal: make the backend/frontend truthful and safe without changing the full economy yet.

Scope:
- Rename/copy language from "automatic weekly royalties" to "claimable creator earnings".
- Remove or disable frontend claims that payouts happen automatically every week.
- Align frontend IDL/UI with backend reality: either expose a claim action or explicitly show claimable-only pending state.
- Document that Tokens are arcade credits and Tickets are non-cash prize/perk points.
- Add tests/search checks proving no public weekly-auto-payout promise remains.

Evidence:
- Changed files list.
- Search output for removed misleading phrases.
- Frontend/static validation tests where available.

## Phase 2 — Safe claim flow hardening

Owner: Iamj implementation, Jmai verification, Gmai review.

Goal: make claimable ICP earnings safe before real volume.

Scope:
- Replace or wrap `claimRoyalties()` with a safe claim function that avoids double-claim/interleaving risk.
- Debit/lock before ledger `await`; restore balance if transfer fails.
- Add minimum claim threshold if appropriate.
- Keep balances ICP-denominated in e8s.
- Avoid mixing ticket units with ICP e8s.
- Add tests for:
  - claim succeeds once
  - repeated/overlapping claim cannot double-pay
  - failed transfer restores balance
  - anonymous caller is rejected
  - zero/dust balances are rejected

Evidence:
- Backend tests or static regression tests.
- Candid/interface diff if methods change.

## Phase 3 — Economy unit cleanup

Owner: Iamj implementation, Jmai verification, Gmai review.

Goal: remove unit ambiguity between ICP e8s, Tokens, and Tickets.

Scope:
- Audit every write to creator earnings/royalties.
- Ensure creator earnings map stores only ICP e8s.
- Separate refunds from creator earnings if the code currently uses one bucket for both.
- For NFT redemptions paid with Tickets, decide one of:
  1. record ticket-based seller credit separately, not as ICP;
  2. convert to ICP e8s only via an explicit backed formula;
  3. defer seller payouts until the NFT sale flow has a funded ICP source.
- Update dashboard labels accordingly.

Evidence:
- Unit audit doc.
- Tests for each earning source.

## Phase 4 — Product dashboard polish

Owner: Iamj implementation, Jmai verification, Gmai review.

Goal: make the creator/seller dashboard understandable.

Scope:
- Show claimable earnings clearly.
- Explain that claiming is manual.
- Keep Tokens/Tickets copy closed-loop.
- Add responsible copy: creators are responsible for their own tax reporting; no tax advice.
- Optional: category breakdown can be display-only if derived safely from events.

Evidence:
- Screenshot or DOM/text validation.
- Search check for old terminology.

## Phase 5 — Deploy validation

Owner: Jmai, with Gmai deploy review.

Goal: safe deployment only after code review.

Scope:
- Build/check Motoko.
- Compare Candid compatibility if methods change.
- Preflight backend canister `pifyq-raaaa-aaaab-agrqq-cai`.
- Deploy only with explicit deploy authorization.
- Post-deploy smoke tests:
  - homepage loads from `mprew`
  - backend queries work on `pifyq`
  - creator earnings query works
  - claim path is either disabled or safely functional depending on completed phase

## Current execution plan

Start with Phase 1 immediately. Do not deploy in Phase 1. After Phase 1 passes review, continue to Phase 2 unless Jay changes direction.
