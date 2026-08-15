# Creator Earnings Pivot — Phase 1 Dashboard Revision Evidence

Date: 2026-04-25
Project: ICP-ARCADE / Infinity Arcade
Deploy status: **not deployed**

## Summary

Addressed the remaining Gmai re-review blocker in the Developer Dashboard copy.

Changed:
- Dashboard summary label no longer says `TOKENS EARNED`; it now shows claimable ICP framing.
- Per-game developer rows no longer display `${devEarned} Tokens`; they show ICP claimable creator earnings language.
- Earnings log no longer has a `TOKENS` creator-earnings column; it now shows claimable ICP.
- CSV export no longer includes `Dev Earnings (Tokens)`; it now exports `Creator Earnings (ICP)`.
- The Phase 1 validator now rejects stale dashboard/CSV creator-earnings-as-Tokens copy.

## Files changed

- `index.html`
- `scripts/validate-creator-earnings-phase1.mjs`
- `docs/plans/2026-04-25-creator-earnings-phase1-dashboard-revision-evidence.md`

## Validation

Command:

```powershell
node scripts\validate-creator-earnings-phase1.mjs
```

Result:

```text
creator earnings phase1 copy/IDL checks passed
```

Targeted public-copy search:

```powershell
rg -n -i "TOKENS EARNED|Dev Earnings \(Tokens\)|devEarned\}\s*Tokens|developer earnings[^\n]*Tokens|creator earnings[^\n]*Tokens|withdrawable to ICP|paid out automatically every week|getAllRoyalties|getTreasuryLaneBalances" index.html manifesto.txt
```

Result: no matches.

## Residual risk

- This is still source-only copy/interface alignment. No frontend or backend deploy was performed.
- Backend `claimRoyalties()` hardening remains Phase 2 and should be completed before this creator-earnings model is treated as production-safe money flow.
