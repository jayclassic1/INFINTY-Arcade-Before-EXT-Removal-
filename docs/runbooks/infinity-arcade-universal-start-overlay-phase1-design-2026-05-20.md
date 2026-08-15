# Infinity Arcade Universal Start Overlay - Phase 1 Design Lock

Date: 2026-05-20
Project: ICP-ARCADE / Infinity Arcade
Scope: Phase 1 design lock only. No code patch, deploy, backend mutation, ticket change, or payout change in this phase.

## Decision

Build a universal Arcade shell Start overlay for every Showroom game launch.

The Start overlay is a platform-level control owned by the Infinity Arcade parent shell. It should not be injected into uploaded game files and should not require each builder to invent their own focus, click, or browser-activation path.

## Why

Swing Blade exposed a browser/iframe activation problem: keyboard Space could fail depending on timing, focus, cache, browser, or iframe readiness. A real click/tap path is more reliable because browsers treat it as a trusted user gesture.

The same class of issue can affect future uploaded games. The right root fix is a shared shell-level activation path plus a simple builder input contract.

## Visual Contract

- Label: Start
- Placement: top-right of the gameplay area, inside the game modal shell.
- Applies to: all Showroom game launches, including regular games and ticket-payout games.
- Style: visible, compact, readable, and clearly part of the Arcade shell.
- It should not look like an error state, repair button, or reset control.

## Runtime Contract

When clicked, the universal Start overlay should:

- use the player click/tap as the trusted activation gesture
- focus the active game iframe
- send standard Arcade input messages to the game iframe:
  - arcade-key action a down
  - arcade-key action a up
  - arcade-key action start down
  - arcade-key action start up
- optionally send an arcade-start message as a future-friendly explicit signal
- dismiss itself after the activation attempt

## Hide And Reset Rules

The overlay should hide when:

- the player clicks Start
- the game sends arcade-game-interaction
- the game sends arcade-input-ready
- the game sends score or game-over messages
- the game modal closes
- the iframe is removed

The overlay should reset and reappear when:

- a new game iframe is loaded from the Showroom play path
- a paid session is replayed after an existing session resumes
- a demo iframe is loaded

## Builder Contract

Builder eligibility now requires support for Arcade parent input messages. Games should treat action a and/or action start as Start/Confirm when the game is waiting to begin.

The universal Start overlay can focus an iframe and send the standard messages, but it cannot reliably start a game that ignores the Arcade input contract.

Builder-facing documentation lives at:

- docs/runbooks/infinity-arcade-builder-eligibility-standard.md
- docs/runbooks/infinity-arcade-game-submission-requirements.md

## Current Swing Blade State

Swing Blade currently has a native in-game Start button. Do not remove it in Phase 1.

Recommended handling:

- Keep it temporarily as a game-side fallback while the universal shell overlay is built and tested.
- In a later phase, either move it top-right for visual consistency or remove/hide it if the shell overlay fully covers the need.

## Non-Goals For Phase 1

- No deploy.
- No backend change.
- No canister upgrade.
- No ticket payout change.
- No score submission change.
- No removal of the Swing Blade native Start button.
- No rewrite of uploaded games.

## Phase 1 Acceptance Criteria

- Universal Start overlay design is locked.
- Builder eligibility docs mention the universal Start overlay and Arcade input contract.
- Implementation phase can proceed without unresolved product ambiguity.

