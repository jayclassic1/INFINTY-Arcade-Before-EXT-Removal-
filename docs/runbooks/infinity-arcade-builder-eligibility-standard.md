# Infinity Arcade Builder Eligibility Standard

Use this as the builder-facing standard for games that want to be eligible for Infinity Arcade Showroom or on-chain upload. This applies to regular games and ticket-payout games.

## Eligibility Baseline

A game is eligible for Arcade review only if it:

- Runs as a static browser game.
- Runs inside an iframe.
- Works in Chromium browsers and Firefox.
- Has an index.html entry point.
- Does not require a server, Node runtime, CDN script, remote asset fetch, wallet call, canister call, or external API during gameplay.
- Keeps all economy, wallet, payout, and score-submission behavior at Arcade session boundaries.
- Submits or exposes only positive integer scores where higher is better.
- Treats ticket-payout behavior as explicit. A regular game must not pretend to be ticket-backed.

## Universal Start Overlay Requirement

Infinity Arcade should provide a platform-level Start overlay for every Showroom game launch, whether the game is a regular game or a ticket-payout game.

The Start overlay belongs to the Arcade shell, not to each uploaded game. This keeps the launch path consistent and avoids asking every builder to invent their own focus, gesture, and iframe activation logic.

The shell Start button should:

- Appear in the top-right of the gameplay area when a game iframe opens.
- Use a real player click/tap as the trusted activation gesture.
- Focus the game iframe.
- Send the standard Arcade Start/Confirm input messages into the iframe.
- Hide after the player clicks it or after the game reports interaction, input readiness, score, or game-over.
- Work for both paid regular games and ticket-payout games.

The overlay is a failsafe for browser focus and input activation. It is not a replacement for game-side input support.

## Required Game Input Contract

Eligible games must support the parent Arcade postMessage input path.

Minimum inbound message:

    {
      type: 'arcade-key',
      player: 0,
      action: 'left' | 'right' | 'up' | 'down' | 'a' | 'b' | 'c' | 'd' | 'start',
      state: 'down' | 'up'
    }

Builder rules:

- Map a and/or start to Start, Confirm, Jump, or the primary action when the game is waiting for activation.
- Keep native keyboard input working.
- Treat down followed by up as one deliberate press.
- Do not repeatedly fire one-shot actions every frame while a key is held.
- Ignore unknown actions safely.
- Do not require direct DOM access from the parent shell.

The universal shell Start overlay can focus any iframe, but it can only start a game reliably when the game honors this input contract.

## Optional Game-Side Start Button

An individual game may also include its own in-game Start button. This is optional and useful for official or tightly integrated games.

If a game includes its own Start button:

- Use the exact label Start.
- Keep it visually consistent with the game.
- Use the same internal start path as keyboard or arcade-key Start.
- Hide it once gameplay begins.
- Do not add separate error labels such as Reset, Fix Input, or Re-arm Controls.

The platform-level Start overlay remains the required universal failsafe.

## Showroom Zip Requirements

For on-chain Showroom upload:

- Zip size must be 10 MB max.
- No individual uncompressed file may exceed 2 MB.
- Include index.html at the root or inside one top-level folder.
- Bundle required HTML, CSS, JavaScript, images, fonts, and audio.
- Exclude node_modules, .git, __MACOSX, .DS_Store, source-only folders without built output, and oversized files.
- Prefer compressed images and OGG/MP3 audio.

## Runtime Safety Requirements

During gameplay, a game must not:

- Call ICP, wallet, canister, payment, broker, or external market APIs.
- Fetch remote scripts or assets.
- Submit scores continuously.
- Modify parent page state outside the approved Arcade message contract.
- Trigger downloads, popups, wallet prompts, phishing flows, or hidden redirects.
- Obfuscate behavior that reviewers cannot inspect.

Allowed session-boundary messages include score/game-over notifications and optional Arcade integration requests such as player info or inventory, when supported by the shell.

## Ticket-Payout Game Requirements

Ticket-payout games must:

- Declare ticket-payout status explicitly.
- Use Arcade session start and game-over boundaries for spend and payout logic.
- Produce deterministic positive integer score output.
- Avoid local-only score mutation after final game-over.
- Never claim payout unless Arcade backend rules confirm it.

Ticket payout is an Arcade/backend responsibility. The game only reports gameplay result data.

## Minimum Review Checklist

Before a builder's game is eligible for Arcade approval:

- [ ] Runs standalone.
- [ ] Runs embedded in an iframe.
- [ ] Works in Chromium.
- [ ] Works in Firefox.
- [ ] Works with native keyboard input.
- [ ] Works with Arcade arcade-key messages.
- [ ] Responds to a and/or start as Start/Confirm when waiting to begin.
- [ ] Does not require external runtime assets for Showroom/on-chain mode.
- [ ] Does not call network, wallet, backend, or canister APIs inside the frame loop.
- [ ] Produces positive integer score output.
- [ ] Clearly declares regular-vs-ticket-payout behavior.
- [ ] Passes file-size and zip packaging requirements.
- [ ] Does not include malicious, hidden, phishing, obfuscated, auto-download, or exploit behavior.

## Builder Prompt

Build a browser game for Infinity Arcade Showroom eligibility:

- Create a complete static web game with index.html as the entry point.
- The game must run standalone and inside an iframe.
- The game must work in Chrome/Brave and Firefox.
- The final zip must be under 10 MB, and no file may exceed 2 MB uncompressed.
- Bundle all assets locally; do not use runtime CDNs, remote images, remote audio, external APIs, backend servers, wallet APIs, ICP/canister APIs, Node runtime, or package installs.
- Implement native keyboard controls.
- Also implement window message support for Infinity Arcade arcade-key messages with actions left, right, up, down, a, b, c, d, and start, with states down and up.
- Map a and/or start to Start/Confirm or the primary action when the game is waiting to begin.
- Track held input correctly so one-shot actions fire once per press.
- Use requestAnimationFrame for the game loop.
- Keep all wallet, payment, payout, and score-submission behavior outside the frame loop.
- If the game has scoring, output a positive integer where higher is better.
- Include a clear game-over or completion state.
- Provide final files in a zip-ready structure with no node_modules, .git, __MACOSX, .DS_Store, hidden junk files, or oversized files.

