# Infinity Arcade — Mainnet runbook

Everything below runs from the project folder. `-e ic` means mainnet. Canister IDs are saved by the
CLI in `.icp/data/mappings/ic.ids.json` — **never delete that file**, it is the only link between the
canister names and their on-chain IDs.

## 0. One-time repo prep (already done by the prep scripts)
- `index.html` has an `ARCADE_ENVS` block with `local` and `ic` entries; the page picks one by hostname.
- The canister controller (your `icp identity`) counts as admin in `arcade_backend` and `nft_canister`,
  so all wiring below is plain terminal calls.
- `.gitignore` must keep `.icp/data/` (the mappings) but ignore `.icp/cache/`.

## 1. Identity and funding
```
icp identity list
icp identity new mainnet            # skip if you already have a non-anonymous identity
icp identity default mainnet
icp identity principal              # the CONTROLLER principal (not your Internet Identity)
icp identity account-id             # send ICP here from your wallet/exchange
icp token balance -e ic
```
Back up the identity's `.pem` file somewhere safe (it controls the canisters).

## 2. Cycles
Creating 4 canisters costs ~2T cycles each (8T). Mint ~30T so the backend has headroom:
```
icp cycles mint --cycles 30t -e ic
icp cycles balance -e ic
```

## 3. First deploy (creates all four canisters)
```
scripts/deploy.sh ic first-time
```
The site will show a red "Mainnet canister IDs are not configured" banner — expected until step 4.

## 4. Put the IDs into the site
Open `.icp/data/mappings/ic.ids.json` and copy the IDs into `index.html` → `ARCADE_ENVS.ic`:
`backend` = arcade_backend, `nft` = nft_canister, `games` = game_assets. Leave `admins` as is for now.
```
scripts/deploy.sh ic frontend
```
Open `https://<frontend-id>.icp0.io`, log in with Internet Identity, open your Profile and copy your
principal. **It is different from your local one** (II principals depend on the site's address).
Put it in `ARCADE_ENVS.ic.admins`, then:
```
scripts/deploy.sh ic frontend
```

## 5. Wire the canisters (replace the three placeholders)
```
icp canister call arcade_backend adminAddAdmin '(principal "<YOUR-MAINNET-II-PRINCIPAL>")' -e ic
icp canister call arcade_backend adminSetNftCanisterId '("<NFT-CANISTER-ID>")' -e ic
icp canister call nft_canister addAdmin '(principal "<YOUR-MAINNET-II-PRINCIPAL>")' -e ic
icp canister call nft_canister addOperator '(principal "<BACKEND-CANISTER-ID>")' -e ic
icp canister call game_assets grant_permission '(record { to_principal = principal "<YOUR-MAINNET-II-PRINCIPAL>"; permission = variant { Commit } })' -e ic
```
Verify:
```
icp canister call arcade_backend getAdmins -e ic
icp canister call nft_canister getOperators -e ic
icp canister call arcade_backend getPayoutsPaused -e ic
icp canister status arcade_backend -e ic
```

## 6. Content
In the site's admin panel (logged in with the mainnet principal): upload each game with
**Upload Game to Chain**, generate and insert its run key, set monetization/platform, and fund the
Ticket Reserve for ticket games. Mint official NFT collections from the NFT tab.

## 7. Day-to-day
```
scripts/deploy.sh ic frontend        # website changes
scripts/deploy.sh ic backend         # backend upgrades (state is kept)
icp canister top-up --amount 10t arcade_backend -e ic
icp canister status arcade_backend -e ic
```
Never run a bare `icp deploy -e ic` after the first time: it would re-sync `game_assets` from the
repo and delete the uploaded games. `scripts/deploy.sh` never touches `game_assets`.

## 8. Before public launch (after beta)
- `backend/main.mo`: `ALLOW_TEST_MINTING : Bool = false`, then `scripts/deploy.sh ic backend`.
- `index.html`: set `ARCADE_ENVS.ic.beta` to `''` to remove the beta ribbon.
- Regenerate every game's run key.
- Custom domain: if you add one, set it up with Internet Identity "alternative origins" first, or
  every user's principal (and yours) changes with the new address.
