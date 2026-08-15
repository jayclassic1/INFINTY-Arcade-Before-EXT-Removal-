# Infinity Arcade Swing Blade Cloud/Angel Update - 2026-06-14

## Scope

Task: `infinity-arcade-swing-blade-cloud-angel-update`
Project: `ICP-ARCADE`
Output lane: `project_source`

## Files changed

- `games/swing-blade/index.html`
  - Raised cloud spawn offsets from `65-120px` above red platforms to `115-190px`, keeping the `Math.max(18, ...)` top-screen clamp.
  - Changed angel lifecycle so the single angel activates on the first cloud landing and remains active after the player leaves the cloud instead of being deactivated on non-cloud frames.
- `games/swing-blade/tests/swing-blade-static.test.cjs`
  - Adds a focused static verification for inline script parseability, cloud spawn height bounds, and persistent angel lifecycle behavior.

## Verification

- `node games\\swing-blade\\tests\\swing-blade-static.test.cjs` — passes.
- `git diff --check -- games/swing-blade/index.html games/swing-blade/tests/swing-blade-static.test.cjs docs/runbooks/infinity-arcade-swing-blade-cloud-angel-update-2026-06-14.md` — run before commit.

## Residual risk

No browser playtest was performed in this task. Static checks cover the requested lifecycle and spawn-height changes, but feel/balance should still be validated interactively before release.
