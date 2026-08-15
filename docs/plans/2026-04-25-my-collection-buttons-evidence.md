# My Collection Button Cleanup Evidence

Date: 2026-04-25 / 2026-04-26 UTC
Project: ICP-ARCADE / Infinity Arcade
Deploy authorized: false

## User request

Remove the `Gashapon Tickets` and `Mint NFT` buttons from the My Collection page. Keep `Scan` available.

## Changes

- Added a stable `id='gashaponTicketsBtn'` to the Gashapon Tickets button in `index.html`.
- Updated `showTab(tab)` so:
  - `Gashapon Tickets` is hidden when `tab === 'collection'`.
  - `Mint NFT` is hidden by tab logic.
  - `Scan` remains visible on the My Collection tab.
- Added `scripts/validate-my-collection-buttons.mjs` to prevent regression.

## Validation

Commands run from `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`:

```powershell
node scripts\validate-my-collection-buttons.mjs
node scripts\build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Results:

```text
My Collection button validation PASSED (5/5)
Frontend publish payload written to .deploy/frontend-public
Files: 35
Predeploy check passed. Verified frontendCanister=mprew-viaaa-aaaah-quola-cai and frontendDeploySource=.deploy/frontend-public.
Sanitized payload files: 35
```

## Notes

No deploy was performed for this UI change. It still needs Gmai review before any frontend deploy.
