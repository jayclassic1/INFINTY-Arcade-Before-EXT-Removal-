# Infinity Arcade Gameplay Window Frontend Deploy Evidence - 2026-05-11

## Scope
Frontend-only asset deploy for the approved gameplay window UI/copy update.

## Target
- Source root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Production URL: `https://mprew-viaaa-aaaah-quola-cai.icp0.io/`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai` (not mutated)

## Commit reviewed
- `f040726a1b9270ae49461c43f84c89343cb7ca1c` — `Update Jay gameplay window labels`
- Gmai pre-deploy review: APPROVE (`docs/plans/2026-05-11-gameplay-window-final-gmai-review.md`)

## Predeploy checks
- `node scripts\test-gameplay-window-copy.mjs` — PASS
- `node scripts\test-ticket-pool-visibility.mjs` — PASS
- `node scripts\validate-paid-session-score-flow.mjs` — PASS
- `node scripts\build-frontend-publish.mjs` — PASS, generated 35-file sanitized payload
- `scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai` — PASS
- `node scripts\guard-icp-deploy-identity.mjs` — PASS; controller identity verified for frontend and backend

## Payload isolation note
`games/swing-blade/index.html` had unrelated local dirty changes. The deploy payload copy for `games/swing-blade/index.html` was overwritten from reviewed commit `f040726a` before deploy so the frontend upload did not include the unrelated Swing Blade change.

## Backup
Predeploy live index backup saved at:
`docs/plans/live-index-backups/mprew-index-20260511T190145Z.predeploy.html`

## Deploy command
`node scripts\run-icp-tool.mjs icp deploy frontend --environment ic -y --identity mcp-identity --identity-password-file /mnt/c/Users/Jesse/.openclaw/secrets/icp-cli/mcp-identity.password --json`

## Deploy result
```json
{"canisters":[{"name":"frontend","canister_id":"mprew-viaaa-aaaah-quola-cai","url":"https://mprew-viaaa-aaaah-quola-cai.icp0.io/"}]}
```

## Live verification
Fetched `https://mprew-viaaa-aaaah-quola-cai.icp0.io/index.html` with cache-busting query.

Observed markers:
- `INSERT TOKEN`: true
- `INSERT COIN`: false
- `Leave Game`: false
- `Force Close`: false
- `Submit Score`: true
- `icparcade.dev`: false
- `ewgfh-vqaaa-aaaah-qtixa-cai`: false
- `pifyq-raaaa-aaaab-agrqq-cai`: true
- Gameplay `openBackroomGame` section contains payout ladder call: false

Canister status after deploy:
- `mprew-viaaa-aaaah-quola-cai` running/responding
- Controllers include `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`

## Mutation boundary
Frontend asset upload only. No backend deploy, no WASM install, no controller/settings change, no canister lifecycle mutation.
