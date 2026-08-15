# Game Creating Tips

Future-session reference for building Infinity Arcade games without repeating the Swing Blade Firefox/Tester input/focus problem.

## Core rule

Games should work the same for every account type, browser, and device. Do not assume a game is ready because it works for an admin account in one browser.

Before a game is considered ready, test it as:
- Jay/admin in Brave or Chrome
- Jay/admin in Firefox
- Tester/regular account in Brave or Chrome
- Tester/regular account in Firefox
- Mobile, if the game is intended to support mobile

## Input and focus

### Support both native iframe input and parent-forwarded input

Infinity Arcade games often run inside an iframe. Browsers handle iframe focus differently, especially Firefox. A game should support:

1. Native `keydown` / `keyup` events inside the game iframe.
2. Parent Arcade `postMessage` controls using `arcade-key` messages.

Recommended message shape:

```js
{
  type: 'arcade-key',
  player: 0,
  action: 'left' | 'right' | 'up' | 'down' | 'a' | 'b' | 'c' | 'd' | 'start',
  state: 'down' | 'up'
}
```

Game-side guidance:
- Map `left/right/up/down` to movement.
- Map `a` and `start` to primary confirm/jump/start behavior when appropriate.
- Map `b/c/d` to secondary actions when appropriate.
- Only fire `justPressed` on an up-to-down transition. Do not refire every frame while held.
- Ignore unknown actions and invalid states safely.
- Keep native keyboard support even after adding `arcade-key` support.

### Do not rely on one focus click

A transparent “click to focus” overlay can help, but it can also steal the first click or behave differently by browser.

Overlay guidance:
- Dismiss on `pointerdown` and `click`.
- Disable pointer events before removal.
- Include a fallback timer after focus attempts.
- Retry iframe focus after game launch.
- Never leave a hidden overlay sitting above the game canvas.

## Canvas and rendering

### Avoid browser-specific scaling problems

Canvas games should not depend on one browser’s scaling behavior.

Recommended practices:
- Use a fixed internal game resolution only if you also test stretched display output.
- Consider device-pixel-ratio-aware scaling for crisp but stable rendering.
- Avoid excessive CSS effects around a constantly repainting canvas.
- Be careful with `image-rendering: pixelated` / `crisp-edges`; verify Firefox and Chromium both look smooth.
- Keep the game iframe/container simple during active gameplay.

### Frame loop rules

Use `requestAnimationFrame` and keep the hot loop clean.

Guidance:
- Cap large delta times after tab switching or lag spikes.
- Do not call backend/canister APIs in the per-frame loop.
- Do not query inventory, wallet, score, or account state every frame.
- Keep particles, shadows, text effects, and object counts bounded.
- Prefer deterministic input state updated from events, not expensive polling-only logic.

## Arcade integration

### Keep game runtime and backend economy separate

The game should feel instant. Backend calls belong at session boundaries:
- Insert coin / spend token before game starts.
- Save checkpoint only when needed.
- Submit score after game over or explicit submit.
- Claim/withdraw flows outside the game loop.

Do not put ICP, wallet, NFT, or payout calls inside frame updates.

### Use the parent Arcade contract intentionally

When a game is embedded in Infinity Arcade, document which messages it expects and sends.

Common inbound messages a game may receive:
- `arcade-key`
- `PLAYER_INFO`
- `NFT_INVENTORY`
- `SCORE_SUBMITTED`

Common outbound messages a game may send:
- `GET_PLAYER_INFO`
- `GET_NFT_INVENTORY`
- score/session completion messages, if supported by the parent

If a message is optional, the game must keep working when it is missing.

## Account and browser testing

### Always separate these variables

When a bug appears, test one variable at a time:
- Browser: Firefox vs Brave/Chrome
- Account: admin vs regular Tester
- Device: desktop vs mobile
- Mode: standalone game file vs embedded Arcade iframe
- Input: keyboard vs gamepad vs on-screen controls

A good minimum matrix:

```text
Admin + Brave/Chrome
Admin + Firefox
Tester + Brave/Chrome
Tester + Firefox
```

If only one combination fails, suspect browser/account integration, focus, permissions, or iframe messaging before rewriting game physics.

## Score and economy safety

### Ticket games

Ticket-backed games must use the ticket-game path and validate:
- token spend routes correctly
- score threshold pays expected Tickets
- game backed pool decreases on payout
- player ticket liability increases on payout
- protected reserves remain coherent

### Normal/backroom games

Normal games should not accidentally look like ticket-backed games.

Guidance:
- Use backend `gameTier` as the source of truth for ticket-vs-normal behavior.
- Do not default missing `paysTickets` fields to true.
- Hide or disable UI for backend methods that do not exist yet.
- Decide clearly whether a normal game is only an external link/discovery item or a paid embedded Arcade session.

## Validators to keep current

When changing game controls or embedding behavior, run or add validators for:
- input bridge / `arcade-key` support
- paid session score flow
- payment error sanitization
- source/deploy payload sync
- no backend/canister call added to game runtime by accident

For Swing Blade, the current validator is:

```powershell
node scripts\validate-swing-blade-input-bridge.mjs
```

## Deployment safety

For Infinity Arcade frontend changes:
- Build the sanitized frontend payload first.
- Deploy only `.deploy/frontend-public`.
- Do not deploy the project root.
- Do not deploy legacy trees.
- Backend upgrades require separate explicit approval.
- Preserve or confirm a rollback snapshot before risky gameplay-control changes.

Canonical frontend deploy target:
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`

## Practical checklist for a new game

Before adding a new game to Arcade:

- [ ] Runs standalone locally.
- [ ] Runs inside Arcade iframe.
- [ ] Supports native keyboard input.
- [ ] Supports parent `arcade-key` messages.
- [ ] Handles focus overlay/focus retry safely.
- [ ] No backend calls inside the per-frame loop.
- [ ] Canvas/rendering checked in Firefox and Chromium.
- [ ] Tested with admin and regular Tester accounts.
- [ ] Ticket/normal game type is explicit and uses backend `gameTier`.
- [ ] Score/session flow is validated.
- [ ] Sanitized frontend payload is built and checked before deploy.
- [ ] Rollback path is known before live deploy.

## Lesson from Swing Blade

The Swing Blade issue looked like “choppy gameplay” under Tester/Firefox, but the strongest root cause was not the backend or admin privileges. It was browser-sensitive iframe focus/input behavior:

- Parent Arcade forwarded controls as `arcade-key` messages.
- Swing Blade originally ignored `arcade-key` messages.
- Firefox/Tester path exposed the mismatch more clearly.
- Adding game-side `arcade-key` support and hardening overlay dismissal fixed the issue for both Tester and Jay/admin in Firefox.

Default lesson: when embedded game controls feel choppy, first check focus and input routing before assuming frame-rate or backend latency.
