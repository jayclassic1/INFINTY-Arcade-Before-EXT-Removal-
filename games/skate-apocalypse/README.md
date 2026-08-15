# Shred Gnar — Phase 2 Movement Slice

This milestone upgrades the showroom shell into an actual playable movement loop for **Shred Gnar**.

## Smoke expectations

A successful smoke pass for this milestone means:

- the game boots in a browser with no immediate script errors
- the rider auto-pushes forward while the ground scrolls continuously
- left/right change line position and shape speed
- tap jump produces a short hop
- holding then releasing jump adds extra pop and lighter gravity while held
- a hard slam triggers bail, freezes score growth, and shows the restart panel
- pressing **Space** or **R** after a bail restarts the run
- score submission is **not** implemented yet

## Current scope

Included in this slice:
- run-state model with movement, forward speed, and score/combo placeholders
- ground movement, jump hold/release timing, and gravity shaping
- bail loop with restart handling
- updated shell text for the Shred Gnar title

Not included yet:
- air rotation and landing-angle alignment
- flip tricks, grabs, grinds, enemies, or score submission wiring
- final production balancing

## Manual smoke checklist

1. Open `index.html` in a browser.
2. Confirm the ground scrolls and the HUD updates live.
3. Tap **Space** for a short jump.
4. Hold **Space** briefly, then release, and confirm the jump carries higher.
5. Let the rider slam down from a high jump to trigger a bail.
6. Confirm the fail panel appears and score stops increasing.
7. Press **Space** or **R** to restart the run.
