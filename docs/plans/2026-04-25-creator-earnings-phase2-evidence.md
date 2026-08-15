# Creator Earnings Phase 2 Evidence

Task: `icp-arcade-creator-earnings-phase2-safe-claim-20260425`  
Project: `ICP-ARCADE` / Infinity Arcade (Jay Nolan)  
Deploy authorized: no

## Files changed

- `backend/main.mo`
- `scripts/validate-creator-earnings-phase2.mjs`
- `docs/plans/2026-04-25-creator-earnings-phase2-evidence.md`

## Backend claim hardening

`claimRoyalties()` now:

- rejects anonymous callers before state mutation;
- rejects zero royalty balances with `No royalties to claim`;
- rejects dust balances below `ROYALTY_CLAIM_MIN_E8S = 10_000` e8s with a clear e8s-denominated error;
- locks/debits the caller royalty balance with `royalties.put(caller, 0)` before the first ledger `await`;
- performs a single ICP ledger transfer for the locked e8s balance;
- leaves the balance locked at zero on successful transfer;
- restores the locked balance on ledger `#Err`;
- restores the locked balance on transfer trap/catch;
- restores by adding the locked amount to the current royalty balance, preserving any royalties credited while the ledger await was in flight.

The flow remains ICP/e8s-only for creator royalty balances. Tickets remain prize/perk points and are not referenced in the claim body.

## Double-claim / interleaving proof

Motoko actor execution can interleave at `await` boundaries. The hardened claim flow reads the caller's royalty balance, rejects zero/dust, then immediately writes `royalties.put(caller, 0)` before any `await ICP_LEDGER...` call. A repeated or overlapping `claimRoyalties()` call for the same caller therefore observes a zero balance and exits before attempting a second ledger transfer. If the original ledger transfer fails or traps, `restoreRoyaltyBalance(caller, balance)` adds the locked balance back to the current balance.

## Validation output

### Phase 2 static validation

Command:

```powershell
node scripts/validate-creator-earnings-phase2.mjs
```

Result: PASS `11/11`

```text
Creator earnings Phase 2 validation PASSED (11/11)
✅ claimRoyalties exists
✅ claim rejects anonymous callers
✅ claim rejects zero balance with a clear error
✅ claim rejects dust below explicit e8s minimum
✅ claim locks/debits royalty balance before any ledger await
✅ claim restores debited balance on ledger #Err result
✅ claim restores debited balance on transfer trap
✅ restore helper preserves credits accrued while claim awaited
✅ successful claim leaves caller royalty balance locked at zero
✅ claim uses ICP e8s royalties only, not tickets
✅ creditRoyalty documents ICP e8s denomination
```

### Motoko typecheck

Build environment check: ready; dfx `0.32.0`; JS Motoko compiler available.

Command/tool:

```text
icp_check_motoko(project_path="...\\infinity-arcade-Jay\\backend", canister_name="arcade_backend")
```

Result: PASS, `0 error(s), 31 warning(s)`.

Warnings are pre-existing style/safety warnings in the canister snapshot (redundant stable keywords, unused identifiers, existing Nat operator trap warnings). No type errors were introduced by this change.

## Candid compatibility / interface impact

No public or shared method signatures were changed. `claimRoyalties()` remains:

```motoko
public shared(msg) func claimRoyalties() : async Result.Result<Nat, Text>
```

The added `ROYALTY_CLAIM_MIN_E8S` constant and `restoreRoyaltyBalance` helper are private implementation details, so no Candid-visible interface regeneration was required.

## Residual risk

- This pass uses static/procedural validation rather than a local replica ledger integration test. It proves ordering/restoration properties over the Motoko source, but does not execute a mocked ICP ledger transfer in-replica.
- The minimum claim floor is set to the ICP ledger fee-sized value `10_000` e8s. Product may later choose a higher operational minimum.
- Treasury reserve sufficiency is now enforced by ledger transfer failure handling rather than a pre-transfer balance query. This avoids an extra pre-lock ledger await, but user-facing insufficient-funds messaging now comes from the ledger transfer result.

## Deployment

No deploy, install, upgrade, transfer, or canister state mutation was performed.
