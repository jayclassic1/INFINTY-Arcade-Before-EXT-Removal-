# Infinity Arcade Backend Leaderboard Persistence Deploy - 2026-05-14

## Scope

Backend upgrade for Infinity Arcade leaderboard/high-score persistence.

- Project root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Backend canister: `pifyq-raaaa-aaaab-agrqq-cai`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Implementation commit: `33a8548d1faca5c89a7f8fc4e5fe31c0787cbbd2`
- Gmai review commit/artifact: `c1f82028`, `docs/runbooks/infinity-arcade-backend-leaderboard-persistence-gmai-review-2026-05-14.md`

## Human Approval

Jay approved backend deployment if ready, then separately approved replacing the oldest snapshot after snapshot creation failed due to the 10-snapshot canister limit.

## Preflight / Review

- Gmai verdict: `APPROVE`.
- `npm run backend:guard`: PASS.
- `npm run backend:mops:check`: PASS with existing Motoko warnings.
- `npm run backend:check`: PASS, canisters built successfully.
- `npm run deploy:guard`: PASS; `mcp-identity` verified as controller on backend and frontend.
- Pre-upgrade canister status: Running, module hash `0x65448270f833ca825a4c14a05888b18f761fbdb67d0a37531bc0dd5967c02984`, cycles `2_822_945_355_555`.
- Pre-upgrade high scores: `getAllHighScores() = (vec {})`.

## Snapshot Handling

Initial fresh snapshot creation failed because canister `pifyq-raaaa-aaaab-agrqq-cai` had reached the maximum snapshot count of 10.

Oldest snapshot archived before replacement:

- Snapshot ID: `000000000000000c00000000002034610101`
- Taken at: `2026-04-30 06:05:55 UTC`
- Archive path as written by ICP CLI on Windows/WSL path translation: `.releases?snapshots?pifyq-pre-replace-2026-04-30-000c`
- Archive contents included: `metadata.json`, `wasm_memory.bin`, `wasm_module.bin`, `stable_memory.bin`, `.lock`, `wasm_chunk_store/`.

Fresh pre-upgrade snapshot created by replacing the archived oldest snapshot:

```json
{"snapshot_id":"000000000000001600000000002034610101","taken_at_timestamp":1778770056793551364,"total_size_bytes":12226792}
```

Snapshot list after deploy includes new snapshot `000000000000001600000000002034610101`, taken at `2026-05-14 14:47:36 UTC`.

## Deploy Command

```powershell
node scripts\run-icp-tool.mjs icp canister install pifyq-raaaa-aaaab-agrqq-cai --mode upgrade --wasm backend/.build/arcade_backend.wasm --environment ic --identity mcp-identity --identity-password-file /mnt/c/Users/Jesse/.openclaw/secrets/icp-cli/mcp-identity.password -y
```

Result:

```text
Canister pifyq-raaaa-aaaab-agrqq-cai installed successfully
```

The canister was started after upgrade.

## Post-Deploy Verification

Post-upgrade canister status:

- Status: Running
- Module hash: `0x8b9f7c3d782e761983472cef8fea2017225e640055a36e3ca1b765c3347af8d8`
- Local WASM SHA256: `8B9F7C3D782E761983472CEF8FEA2017225E640055A36E3CA1B765C3347AF8D8`
- Cycles: `2_813_717_597_529`
- Memory size: `111_594_352`

Functional checks:

```text
getAllHighScores() = (vec {})
getHighScore("game-1-1777223039629610695") = (null)
getGameBackedTicketPool("game-1-1777223039629610695") = (241 : nat)
getGameRawTicketPool("game-1-1777223039629610695") = (343 : nat)
```

## Outcome

The leaderboard persistence fix is live. Future high scores stored in `leaderboardEntries` should now survive backend upgrades because `postupgrade()` no longer clears the stable leaderboard array before lazy hydration rebuilds the runtime map.

This upgrade does not recover old Swing Blade scores that were already absent from backend stable storage before the upgrade. Recovery would require finding another data source for those historical scores.
