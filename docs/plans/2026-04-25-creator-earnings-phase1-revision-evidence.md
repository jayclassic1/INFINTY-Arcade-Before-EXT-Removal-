# Creator Earnings Phase 1 Revision Evidence

Task: `icp-arcade-creator-earnings-phase1-revision-20260425`
Trace: `0c525b851b6f41cfafa50d5af433c7ac`
Base reviewed commit: `cc49a87be2be8fe150744d90f515081337e266d9`

## Files changed

- `index.html`
  - Replaced stale public copy that said creator revenue is paid in Tokens and withdrawable to ICP.
  - New copy states creator/seller earnings accrue as ICP-denominated claimable earnings tracked separately from arcade Tokens, with manual claim hardening in Phase 2.
- `scripts/validate-creator-earnings-phase1.mjs`
  - Added broader forbidden-public-claim patterns for revenue/creator/seller/developer earnings paid in Tokens and withdrawable/withdraw to ICP.
  - Added a direct guard for `Tokens to your on-chain balance ... withdraw ... ICP` stale-copy shape.
- `docs/plans/2026-04-25-creator-earnings-phase1-revision-evidence.md`
  - This evidence record.

## Verification

1. Regression proof before copy fix
   - Command: `node scripts\\validate-creator-earnings-phase1.mjs`
   - Result: failed as expected on the newly added broad forbidden-language pattern while the stale `index.html` line was still present.

2. Phase 1 validator after copy fix
   - Command: `node scripts\\validate-creator-earnings-phase1.mjs`
   - Result: `creator earnings phase1 copy/IDL checks passed`

3. Targeted stale-language search
   - Command: `rg -n -i "Revenue paid in|withdraw to ICP|withdrawable.*ICP|paid in.*Tokens|creator revenue.*Tokens|creator revenue paid|on-chain balance.*withdraw|1 Token = 0\\.01 ICP|creator/seller earnings|ICP-denominated claimable" index.html manifesto.txt backend\\main.mo scripts\\validate-creator-earnings-phase1.mjs`
   - Result: no stale public `Revenue paid in Tokens ... withdraw to ICP` copy remained. Hits were expected canonical creator/seller claimable wording, validator guard patterns, and an unrelated operating-treasury `Withdrawable profit` label.

## Deployment/canister mutation

None. No deploy, install, upgrade, transfer, or canister mutation commands were run.
