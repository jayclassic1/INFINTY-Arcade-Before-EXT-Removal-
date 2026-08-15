# Economy Split Reconciliation Evidence — 2026-04-25

## Scope
Reconcile Infinity Arcade backend logic and frontend copy to Jay's revenue split:

- Ticket games: 20% creator ICP earnings, 70% ticket pool, 5% DAO, 5% burned
- Non-ticket games: 80% creator ICP earnings, 10% DAO, 10% burned
- NFT sales remain 90% creator / 10% treasury

## Files changed
- `backend/main.mo`
- `index.html`

## Backend changes
- Replaced legacy single `GAME_CREATOR_SHARE = 75` with authoritative ticket and regular split constants.
- Added `isTicketGameSubmission(game)` wrapper used by game-spend accounting.
- Changed ticket pool credit to use `TICKET_GAME_POOL_SHARE` against the 10-ticket-per-token basis.
- Changed `spendTokensOnGame` so:
  - ticket games credit ticket pool and creator at 20%
  - regular/non-ticket games do not credit ticket pool and credit creator at 80%
- Expanded `getRevenueSplits()` to expose ticket and regular split fields while preserving legacy-compatible fields.

## Frontend changes
- Updated developer-facing split copy:
  - Ticket games: 20% creator / 70% pool / 5% DAO / 5% burn
  - Non-ticket games: 80% creator / 10% DAO / 10% burn
- Preserved closed-loop Tickets and ICP e8s claimable earnings language.

## Verification

```text
node scripts/validate-economy-splits.mjs
Economy split validation PASSED (6/6)
```

```text
icp_check_build_env(check_updates=false)
ready: true
missing_tools: []
dfx_version: dfx 0.32.0
moc-js: available
```

```text
icp_build_motoko(project_path=backend, canister_name=arcade_backend)
success: true
wasm: backend/.build/arcade_backend/arcade_backend.wasm
wasm_size_bytes: 741117
compiler: moc-js
```

## Deploy status
No deploy performed. Gmai review required before deploy approval request.
