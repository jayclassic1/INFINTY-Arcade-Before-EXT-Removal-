# Infinity Arcade Game Card Stats UI Plan — 2026-05-14

Scope: frontend UI only; no backend payout/config logic changes and no deploy.

## Phases

1. **Public game-card/modal stats**
   - Show public `Prize` estimate beside the creator label above the game image.
   - Source the prize estimate from the game-backed ticket pool.
   - Round public prize values down to the nearest 100; show `0` for zero and `<100` for nonzero values below 100.
   - Show the clean/validated all-time high score beside it.

2. **Details UI simplification**
   - Hide payout ladder display from public/admin details modal surfaces.
   - Hide ticket jackpot tier/status display from details modal surfaces.
   - Hide the backed ticket pool pill/panel from details/admin details surfaces.
   - Keep backend methods/configs intact.

3. **Testing path**
   - Use Swing Blade as the verification target for ticket payout config and stat display.
   - Compare UI stat reads against live/local canister query values before deploy sign-off.

## Current implementation note

Phase 1 and Phase 2 UI changes are staged in `index.html`. Phase 3 remains a no-deploy verification path for a later live/local canister check.
