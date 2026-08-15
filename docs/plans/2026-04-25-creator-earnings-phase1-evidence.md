# Creator Earnings Pivot — Phase 1 Evidence

Date: 2026-04-25
Project: ICP-ARCADE / Infinity Arcade
Target canisters: frontend `mprew-viaaa-aaaah-quola-cai`, backend `pifyq-raaaa-aaaab-agrqq-cai`
Deploy status: **not deployed**

## Summary

Phase 1 aligns public/product language with the creator-earnings pivot without changing backend money-transfer semantics yet.

Implemented source truth:
- Automatic weekly payout language was removed from public copy.
- Public language now frames revenue as **claimable creator earnings**.
- Tokens are described as arcade credits.
- Tickets are described as prize/perk points that cannot be exchanged for ICP.
- Unsupported frontend assumptions around `getAllRoyalties` and `getTreasuryLaneBalances` are guarded by validation.

## Files changed

- `index.html`
- `manifesto.txt`
- `scripts/validate-creator-earnings-phase1.mjs`
- `docs/plans/2026-04-25-creator-earnings-pivot-phases.md`
- `docs/plans/2026-04-25-creator-earnings-rollback-note.md`
- `docs/plans/2026-04-25-creator-earnings-phase1-evidence.md`

## Validation run

Command:

```powershell
node scripts\validate-creator-earnings-phase1.mjs
```

Result:

```text
creator earnings phase1 copy/IDL checks passed
```

Search gate:

```powershell
rg -n -i "automated weekly earnings|paid out automatically every week|paid out automatically weekly|paid out in weekly batches|redeem(ed)? tickets? for ICP|cash-out|cash out|getAllRoyalties|getTreasuryLaneBalances|claimRoyalties removed|automated weekly batch payout" index.html manifesto.txt
```

Result: no matches.

## Residual risks

- Backend `claimRoyalties()` still exists and has not yet been hardened against interleaving/double-claim risk. That belongs to Phase 2.
- Backend terminology still uses `royalties` internally; Phase 1 avoids broad backend rename to reduce risk.
- This phase does not deploy and does not mutate canister state.

## Rollback

Pre-pivot source tag:

`icp-arcade-pre-creator-earnings-pivot-20260425`

Snapshot commit:

`e0dbe4088fe6a4b9bb770ccb92300bbf72895a12`

Rollback instructions are documented in:

`docs/plans/2026-04-25-creator-earnings-rollback-note.md`

## Next phase

Phase 2 should harden the manual claim path before this is deployed as a real money flow.
