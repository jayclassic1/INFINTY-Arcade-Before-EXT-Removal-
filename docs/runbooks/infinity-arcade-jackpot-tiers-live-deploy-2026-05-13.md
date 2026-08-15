# Infinity Arcade Jackpot Tiers Live Deploy — 2026-05-13

## Scope

Deployed the reviewed 3-tier ticket jackpot release to the active Infinity Arcade canisters only.

- Backend: `pifyq-raaaa-aaaab-agrqq-cai`
- Frontend: `mprew-viaaa-aaaah-quola-cai`
- Git baseline deployed: `438beb7e` — `Harden jackpot deploy readiness guards`
- No legacy canisters targeted.

## Approval

Jay approved the live deploy phase in `#jaynolan` on 2026-05-13 after the deploy summary and after the stop/snapshot/replace-oldest-snapshot gate was explained.

## Snapshot Gate

Backend canister had the maximum 10 snapshots. The oldest snapshot was replaced during fresh snapshot creation after approval.

- Replaced oldest snapshot: `000000000000000b00000000002034610101`
- Fresh pre-upgrade snapshot: `000000000000001500000000002034610101`
- Fresh snapshot size: `12006398` bytes

The backend was stopped only for snapshot/upgrade and then restarted.

## Backend Upgrade

Built and upgraded the active backend canister.

- Local WASM SHA256: `65448270f833ca825a4c14a05888b18f761fbdb67d0a37531bc0dd5967c02984`
- Post-upgrade module hash: `0x65448270f833ca825a4c14a05888b18f761fbdb67d0a37531bc0dd5967c02984`
- Backend status after upgrade: `Running`
- Controllers verified in status: `7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae`, `xcreu-r77dk-scpjr-fua34-suphw-f44ha-gpmwm-i2ncz-hm6uo-zn6f3-xae`

## Frontend Deploy

Used the hardened index-only deploy path for the active frontend canister.

- Live `/index.html` SHA256: `d49713e698ecbd08b7dee5c5a5c63bfe1aa997190baf539f8490cb73fd24b036`
- Local expected `/index.html` SHA256: `d49713e698ecbd08b7dee5c5a5c63bfe1aa997190baf539f8490cb73fd24b036`
- Live SHA verified equal.

## Postdeploy Verification

Backend calls:

- `getAllGameTicketJackpotConfigs()` — returned `(vec {})`
- `getRecentTicketJackpotWinDetails(5)` — returned `(vec {})`
- `getRecentTicketJackpotWins(5)` — returned `(vec {})`
- Snapshot list now includes fresh snapshot `000000000000001500000000002034610101` and no longer includes replaced oldest snapshot `000000000000000b00000000002034610101`.

Live frontend raw index contains:

- `Ticket Jackpot Tiers` — true
- `getRecentTicketJackpotWinDetails` — true
- `jackpotTierLabels` — true
- `new high score bonus can stack` — true
- `setGameTicketJackpotConfig` — true

Live frontend raw index does not contain denied legacy references:

- `icparcade.dev` — false
- `ewgfh-vqaaa-aaaah-qtixa-cai` — false

## Result

Deploy completed successfully. The active live Infinity Arcade now has the 3-tier ticket jackpot backend logic, admin controls, and player/history display support.

## Follow-up

Configure jackpot tiers per game in the admin UI before expecting payouts. Empty config query is expected immediately after deploy because no game-specific tier settings have been saved yet.
