# Gmai Review: Creator Earnings Phase 4 Dashboard Polish

Verdict: FAIL

Reviewed commit: `60dbbb9f353541b0aecc1b5ad8e429da9037ed88`
Task: `gmai-arcade-creator-earnings-phase4-review-20260425`
Trace: `1257b0b2a7064360adde8fe7f32b6d7d`
Deploy authorized: false

## Evidence checked

- Confirmed `HEAD` is the reviewed commit `60dbbb9f353541b0aecc1b5ad8e429da9037ed88`.
- Reviewed changed files:
  - `index.html`
  - `scripts/validate-creator-earnings-phase4.mjs`
  - `docs/plans/2026-04-25-creator-earnings-phase4-evidence.md`
- Inspected the creator earnings dashboard and FAQ/user-facing copy for Phase 4 scope.
- Inspected the commit diff for accidental user-visible regressions.

## Scope findings

The creator earnings copy itself largely satisfies the requested Phase 4 semantics:

- Manual claim is described as current guidance, not future Phase 2 work.
- Creator/seller balances are labeled as ICP e8s claimable earnings.
- Refunds are described as separate ICP refunds that can use the same backend claim flow when present.
- Tokens are described as arcade credits only.
- Tickets are described as prize/perk points only and cannot be exchanged for ICP.
- No automatic weekly creator payout promise was found in the updated creator earnings copy.
- No ticket-to-ICP cashout wording was found by the validator.
- Tax/no-advice copy exists.
- Category breakdown copy is explicitly display-only/deferred and warns not to invent unsupported values.

## Tests run

- `node scripts/validate-creator-earnings-phase1.mjs` - passed
- `node scripts/validate-creator-earnings-phase2.mjs` - PASSED 11/11
- `node scripts/validate-creator-earnings-phase3.mjs` - PASSED 8/8
- `node scripts/validate-creator-earnings-phase4.mjs` - PASSED 9/9

Motoko check was not rerun because this review phase changed frontend copy/validation/evidence only.

## Issues

1. **Blocking: `index.html` contains broad mojibake/encoding regressions introduced by this commit.**

   The commit changes many previously valid Unicode glyphs and symbols into mojibake in user-visible UI and JavaScript strings, outside the creator earnings dashboard copy. Examples from the reviewed diff include:

   - brain emoji labels became mojibake
   - infinity symbols became mojibake
   - refresh emoji labels became mojibake
   - ticket emoji labels became mojibake
   - left-arrow return labels became mojibake
   - ready-size labels using bullet and multiply symbols became mojibake
   - warning labels became mojibake
   - modal close symbols became mojibake
   - slot/gacha/profile emoji arrays and labels were similarly corrupted.

   A targeted scan of `index.html` found many emoji, separator, modal-close, and variation-selector mojibake markers, and the diff shows the corruption was introduced by the reviewed commit. Even though the Phase 4 validation script passes, this is a user-visible regression in the changed frontend file and should not be approved as dashboard polish.

## Residual risk

- The Phase 4 validator does not currently detect encoding/mojibake regressions, so this class of issue can pass automated validation.
- The backend public method name remains `claimRoyalties`; that naming is known residual risk from prior phases, but the UI copy now explains creator earnings/refunds more accurately.
- Category breakdown remains display-only/deferred and should not be treated as audited accounting until a source-of-truth event breakdown exists.

## Next action

Revise before deploy: restore `index.html` to valid UTF-8 for all accidentally corrupted glyphs/symbols, then add an encoding/mojibake guard to validation or CI and rerun the Phase 1-4 validation scripts.
