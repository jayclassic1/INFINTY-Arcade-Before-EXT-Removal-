# Infinity Arcade Anti-Cheat Advice for Game Creators

Use this as a short checklist to make games harder to exploit with bots, macros, autoclickers, speed tools, or browser/devtools manipulation.

## Core rule

Never trust the player’s browser as the source of truth for rewards.

The game can report a score, but the arcade/backend should decide whether that score is believable and payable.

## Practical mitigations

- Keep scores as positive integers only.
- Set realistic max scores per game, per round, and per time played.
- Reject impossible scores, instant wins, negative values, floats, or huge jumps.
- Require a real paid/start session before accepting a score.
- Accept scores only after game over or round completion.
- Add cooldowns between plays.
- Limit plays per hour/day per player.
- Cap ticket/jackpot payouts per play and per day.
- Use backed pools so rewards cannot exceed available backing.
- Store high scores and payout history server-side/on-chain, not only in the browser.
- Do not let the browser directly choose ticket payouts, jackpot wins, or reward amounts.
- Keep randomness server-side/on-chain when rewards depend on it.
- Log suspicious events: too-fast completion, repeated perfect scores, identical timing, rapid retries, unusual score jumps.
- Add manual review for top scores, jackpot wins, or unusually large payouts.
- Make games deterministic enough that scores can be sanity-checked against duration, level, enemies, collectibles, or actions.

## Things to avoid

- Do not calculate rewards only in JavaScript.
- Do not store trusted scores only in localStorage.
- Do not expose admin/debug score buttons in production.
- Do not allow score submission without a valid session.
- Do not pay rewards from raw client messages without backend checks.
- Do not rely on “hidden” frontend variables for security.

## AI Builder Prompt

Add basic anti-cheat protections to this Infinity Arcade browser game:

- Scores must be positive integers only.
- Higher score must mean better score.
- Submit score only after a real game-over/completion state.
- Do not submit score during the frame loop.
- Track elapsed play time and include it with the final score if the arcade supports it.
- Prevent duplicate score submissions for the same round.
- Do not calculate ticket, jackpot, wallet, or payout amounts in the game client.
- Do not trust localStorage, hidden variables, query params, or browser-only state for rewards.
- Add clear internal limits for impossible scores and impossible completion times.
- Keep reward validation ready for backend/on-chain enforcement.
