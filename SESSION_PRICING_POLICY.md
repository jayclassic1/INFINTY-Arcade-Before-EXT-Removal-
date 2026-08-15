# Infinity Arcade Session Pricing Policy

## Core rule
A creator/admin-set token price opens **one live session**.

- `X tokens = one live session`
- `X` is configured by the creator/admin when the game is added to Showroom
- the price is **not** per death
- the price is **not** per retry
- the price is **not** per single run

## Inside a live session
Once a session is opened:
- the player may die and retry repeatedly
- the arcade should not force a post-death paywall prompt
- the player ends the session manually with:
  - `Submit Score & Close`
  - `Force Close`

## Score resolution rule
When the player chooses `Submit Score & Close`, the submitted score is the **latest run score**.

## Product wording guidance
Use wording like:
- `1 Token opens a live session`
- `3 Tokens open a live session`
- `Session Price`

Avoid wording like:
- `per life`
- `per death`
- `insert another token after every run`

## Rationale
This keeps the integration simpler for game developers and reduces arcade-shell complexity:
- one payment event
- one session lifecycle
- one final score resolution
- no death interruption loop
