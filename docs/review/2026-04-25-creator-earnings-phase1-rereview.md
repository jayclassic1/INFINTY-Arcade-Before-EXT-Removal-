# Creator Earnings Phase 1 Re-review

Verdict: REVISE REQUIRED

Evidence checked:
- Commit: `ffe0fc345649d127ccb3b87b4badc4bf29398d23` (`Fix creator earnings stale revenue copy`)
- Changed files: `index.html`, `scripts/validate-creator-earnings-phase1.mjs`, `docs/plans/2026-04-25-creator-earnings-phase1-revision-evidence.md`
- Verified commit did not modify backend Motoko or deploy/canister artifacts.
- Reviewed public creator/revenue copy, validator guards, unsupported IDL/call references, and Phase 1 evidence notes.

Tests run:
- `git show --stat --name-only ffe0fc345649d127ccb3b87b4badc4bf29398d23` - pass; only the three expected files changed.
- `node scripts\validate-creator-earnings-phase1.mjs` - pass: `creator earnings phase1 copy/IDL checks passed`.
- Targeted `rg` searches for forbidden creator-token withdrawal language, weekly auto payout language, ticket-to-ICP language, `getAllRoyalties`, and `getTreasuryLaneBalances` - no unsupported public API call/IDL hits; ticket language correctly says Tickets cannot be exchanged for ICP.
- Regex sample check for the old stale-copy shape - pass; the new validator catches samples like `Revenue paid in Tokens ... withdraw to ICP`.

Issues:
1. âŒ Public Developer Dashboard still frames creator earnings as Tokens:
   - `index.html:665` - `Your games, your revenue, your data`
   - `index.html:675-676` - dashboard metric label `TOKENS EARNED`
   - `index.html:9914` - per-game row renders `${devEarned} Tokens` plus ICP equivalent
   - `index.html:10031` - CSV header includes `Dev Earnings (Tokens),Dev Earnings (ICP)`
   This conflicts with the requested Phase 1 alignment that Tokens remain arcade credits, not creator cash. Even though the old explicit `withdraw to ICP` sentence is gone, the dashboard still tells developers they earned Tokens.
2. âš ï¸ Validator does not catch this remaining class of stale creator-earnings-as-Tokens copy. It catches the old combined `paid in Tokens ... withdraw to ICP` wording, but not labels such as `TOKENS EARNED` / `Dev Earnings (Tokens)` in creator dashboard output.

Residual risk:
- Backend `claimRoyalties()` hardening is still deferred to Phase 2 as documented; no backend money-path mutation was part of this commit.
- Phase 1 remains copy/interface alignment only, but it is not fully aligned yet because developer dashboard/CSV copy still uses Token-denominated creator earnings language.

Next action:
- Revise `index.html` Developer Dashboard and CSV labels/calculations to describe creator earnings as ICP-denominated claimable earnings, not Tokens earned.
- Extend `scripts/validate-creator-earnings-phase1.mjs` to fail on creator/developer earnings labels that use Tokens as the earning unit (`TOKENS EARNED`, `Dev Earnings (Tokens)`, per-game `${devEarned} Tokens`, etc.), while preserving valid player Token-credit language.
