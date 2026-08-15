# Phase 2 Backend/API Surface Audit - Real ICP Spine

Date: 2026-04-29  
Project: ICP-ARCADE / Infinity Arcade (Jay Nolan)  
Scope: local source audit only; no deploy, upgrade, live state mutation, transfer, or canister call.

## Canonical target

- Canonical source tree: `infinity-arcade-Jay` as documented by `CANONICAL.md`.
- Frontend canister target in project metadata: `mprew-viaaa-aaaah-quola-cai`.
- Backend canister target in project metadata: `pifyq-raaaa-aaaab-agrqq-cai`.
- Legacy arcade roots/canisters remain reference-only and were not used for this cleanup.

## Audit findings

### ICP deposit conversion / crediting

- The active frontend uses `convertDepositToTokens(amountE8s)` rather than the disabled legacy `depositTokens` path.
- Backend `convertDepositToTokens` rejects anonymous callers and dust-sized amounts, reads the caller's canister-owned deposit subaccount, performs an ICP ledger transfer, and only credits Tokens after a successful transfer.
- The disabled legacy `depositTokens` method intentionally returns an error telling callers to use `convertDepositToTokens`.

### Duplicate deposit prevention

- Backend has stable `claimedDeposits : [Nat]` plus runtime `claimedSet`.
- Minimal cleanup in this pass made successful deposit conversion record the ledger transfer block index and reject a repeated block index before crediting Tokens.
- `preupgrade` persists `claimedSet.keys()` back into `claimedDeposits`.

### Token spend routing and revenue split surfaces

- `spendTokensOnGame` rejects an existing open paid session before balance deduction.
- It debits Tokens once, branches ticket vs non-ticket games, credits creator ICP-e8s royalties, updates ticket-game raw/backed pools, logs `gameplay` in ICP e8s, and opens the paid session.
- Authoritative split constants are exposed by backend `getRevenueSplits`.
- Minimal cleanup in this pass aligned the frontend manual IDL for `getRevenueSplits` with the backend's full finished-product record fields and normalized gameplay revenue logging to the frontend DAO gaming source allowlist, so local validators can catch future drift.

### Revenue split/accounting and DAO reward policy

- DAO dashboard/admin revenue rendering is centrally filtered through `DAO_GAMING_REWARD_SOURCE_LABELS`.
- Non-gaming platform revenue can remain in logs for audit/history, but it is not rendered as DAO reward funding unless the policy changes.
- Existing validation covers gaming-only DAO copy and stale `getRevenueSplitConfig` compatibility language.

### Creator earnings / claim surfaces

- Creator/seller balances are labeled as ICP e8s claimable earnings, not withdrawable player credits.
- `claimRoyalties` combines creator earnings and separate refund balance, locks both before ledger await, and restores both on transfer failure/trap.
- Minimal cleanup in this pass removed stale frontend IDL-comment wording that described claim hardening as future Phase 2 work.

### Treasury visibility/admin methods

- Backend exposes `getTreasuryBalance` and admin treasury operations.
- Frontend guards optional treasury balance reads with `backendMethodAvailable(...)` and classifies known pending backend-capability misses inline rather than as global fatal banners.
- Existing validators cover expected-missing backend handling and admin panel soft-fail behavior.

### Audit trail/event history surfaces

- Backend exposes `getRevenueLog` and `getRevenueSummary` for platform-wide revenue/event history.
- Backend comments distinguish platform-wide revenue logs from DAO reward accounting.

## Machine-checkable guard added

`npm run test:real-icp-api-surface` runs `scripts/validate-real-icp-api-surface.mjs`, which checks:

1. canonical target documentation,
2. ICP deposit conversion and duplicate-deposit guard,
3. spend routing and paid-session protection,
4. backend/frontend `getRevenueSplits` field alignment,
5. manual creator claim locking/restoration semantics,
6. treasury and audit/event visibility surfaces,
7. frontend use of canonical deposit/claim methods and no legacy `depositTokens` call.

## Remaining cautions

- This was a local source/validator cleanup only. It does not prove the currently installed backend module has this exact API surface.
- Do not claim deployment readiness from this runbook alone. Rebuild/generate Candid in an ICP-enabled environment and run release-gate checks before any live upgrade.
- Network/CSP/actor cleanup remains separately flagged as not fully signed off; do not treat this audit as resolving that acceptance item.
