# Wallet MAX Button Fix Evidence

Date: 2026-04-25 / 2026-04-26 UTC
Project: ICP-ARCADE / Infinity Arcade
Deploy authorized: false

## Bug

Jay reported that clicking the wallet `MAX` button caused a red JS error:

```text
Uncaught ReferenceError: fillMaxWithdraw is not defined
```

Root cause: `fillMaxWithdraw()` existed in `index.html`, but it was not exported onto `window` in the inline-handler compatibility registry near the bottom of the file. The wallet button uses inline `onclick='fillMaxWithdraw()'`, so browser global lookup failed.

## Fix

- Added `['fillMaxWithdraw', fillMaxWithdraw]` to the global export/define list.
- Added `scripts/validate-wallet-globals.mjs` to prevent this specific regression.

## Validation

Commands run:

```powershell
node scripts\validate-wallet-globals.mjs
node scripts\validate-my-collection-buttons.mjs
node scripts\build-frontend-publish.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
```

Results:

```text
Wallet globals validation PASSED (5/5)
My Collection button validation PASSED (5/5)
Frontend publish payload written to .deploy/frontend-public
Files: 35
Predeploy check passed. Verified frontendCanister=mprew-viaaa-aaaah-quola-cai and frontendDeploySource=.deploy/frontend-public.
Sanitized payload files: 35
```

## Deploy status

No deploy was performed for this fix yet.
