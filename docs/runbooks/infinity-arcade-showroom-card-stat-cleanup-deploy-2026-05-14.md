# Infinity Arcade Showroom Card Stat Cleanup Deploy - 2026-05-14

## Scope

Index-only frontend deploy for Infinity Arcade showroom card stat cleanup.

- Project root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Reviewed commits: `c2be10b1`, `16cca279`
- Review commit/artifact: `242714aa`, `docs/runbooks/infinity-arcade-showroom-card-stat-cleanup-gmai-review-2026-05-14.md`

## Change

- Changed `HI` label to `Highest Scored`.
- Kept details popup on the non-compact stats display path: `AVAILABLE TICKETS` + `Highest Scored`.
- Cleaned showroom game card layout so title/byline is simple again and stats render below the thumbnail instead of crowding the header/thumbnail.
- Backend untouched.

## Review

Gmai verdict: `APPROVE`.

Key review finding: details modal still uses `renderCompactGameStats(..., false)` and the card cleanup is scoped to showroom card placement/copy.

## Deploy Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

## Deploy Result

- Predeploy check passed.
- Deploy identity guard passed.
- Stored `/index.html` identity and gzip encodings.
- Live raw `/index.html` verified by deploy script.

Live SHA256:

```text
2d5775240715577a3f2aa448edaceb0b18f7d66499507d97ca4c037981671a7d
```

## Post-Deploy Verification

Live URL checked:

```text
https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html
```

Verification result:

```json
{"HasHighestScored":true,"HasHiLabel":false,"HasAvailableTickets":true,"HasFalseZeroCoercion":false,"Sha":"2d5775240715577a3f2aa448edaceb0b18f7d66499507d97ca4c037981671a7d"}
```

## Note On High Score

The missing high score is expected clean-slate behavior because the backend had no saved leaderboard entries before the persistence fix was deployed. Future validated highs should persist across upgrades.
