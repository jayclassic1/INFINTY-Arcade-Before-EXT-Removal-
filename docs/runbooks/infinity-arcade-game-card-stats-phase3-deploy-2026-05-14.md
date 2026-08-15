# Infinity Arcade Game Card Stats — Phase 3 Deploy Evidence

Date: 2026-05-14
Project: ICP-ARCADE / Infinity Arcade
Commit: dcd65228
Frontend canister: mprew-viaaa-aaaah-quola-cai
Backend canister: pifyq-raaaa-aaaab-agrqq-cai
Deploy type: index-only frontend asset update
Deploy approval: user approved Phase 3/deploy in Discord thread

## Review Gate

Gmai rereview verdict: APPROVE
Review artifact: docs/runbooks/icp-arcade-game-card-stats-gmai-rereview-20260514.md

## Deploy Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy-index-only.ps1 -Deploy
```

## Preflight / Guards

- Built explicit frontend publish payload under `.deploy/frontend-public`.
- `scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai`: PASS.
- `npm run deploy:guard`: PASS; identity `mcp-identity` resolves to controller `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae` on active frontend/backend canisters.
- Prepared index-only identity and gzip store args.

## Deploy Result

- Stored `/index.html` identity encoding: PASS.
- Stored `/index.html` gzip encoding: PASS.
- Live raw `/index.html` SHA verified after deploy.

Expected/live identity SHA256:

```text
2f5f83d242ecf657178447ec4a4c00e7aac4214475d5e109c0aeeaa80997fa71
```

Live URL checked:

```text
https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html
```

## Phase 3 Live Backend Verification

Live game submission for Swing Blade:

```text
id = game-1-1777223039629610695
name = swing blade
developer = jay
tier = showroom
status = live
```

Live backend queries:

```text
getGameBackedTicketPool("game-1-1777223039629610695") = 241
getGameRawTicketPool("game-1-1777223039629610695") = 343
getHighScore("game-1-1777223039629610695") = null
```

Expected public UI result:

```text
Prize Pool: ~200 tickets
High Score: -- / none yet
```

## Notes

- Backend payout/config logic was not changed.
- Phase 2 UI simplification is frontend-only.
- No package install or lockfile change was performed.
- Browser live page loaded and deployed module contains the exact high-score formatter. Full authenticated in-browser modal screenshot remains pending if Jay wants visual confirmation inside a logged-in session.
