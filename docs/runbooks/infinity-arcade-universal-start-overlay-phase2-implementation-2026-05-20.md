# Infinity Arcade Universal Start Overlay - Phase 2 Implementation

Date: 2026-05-20
Project: ICP-ARCADE / Infinity Arcade
Scope: Local frontend implementation only. No deploy, backend mutation, ticket change, payout change, or canister upgrade.

## Built

- Added a universal Arcade shell Start overlay button to the game modal.
- The overlay appears top-right in the gameplay area when paid or demo game iframes load.
- Clicking Start focuses the active iframe and sends:
  - arcade-key action a down
  - arcade-key action a up
  - arcade-key action start down
  - arcade-key action start up
  - arcade-start as an explicit future-friendly signal
- The overlay hides after click, game interaction, input-ready, score/game-over, or modal close.
- The paid and demo iframe launch paths now use arcadeVersionedGameUrl() to add arcadeStartVersion to eligible game URLs.
- Swing Blade's native in-game Start button was preserved as a fallback.

## Files Changed

- index.html
- scripts/validate-universal-start-overlay.mjs
- docs/runbooks/infinity-arcade-universal-start-overlay-phase2-implementation-2026-05-20.md

## Verification

- PASS: node scripts/validate-universal-start-overlay.mjs
- PASS: node scripts/validate-swing-blade-input-bridge.mjs
- PASS: node scripts/validate-swing-blade-keymap-resilience.mjs
- PASS: non-module embedded script parse via Node Function constructor

## Not Done

- Not deployed.
- Not reviewed by Gmai yet.
- No backend/ticket/payout change.
- No Swing Blade native Start button removal.

## Next Gate

Phase 3 should run review and browser smoke evidence before any frontend deploy.

