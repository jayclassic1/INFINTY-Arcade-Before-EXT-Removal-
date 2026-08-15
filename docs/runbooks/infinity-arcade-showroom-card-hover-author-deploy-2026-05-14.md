# Infinity Arcade Showroom Card Hover / Author Deploy - 2026-05-14

## Scope

Index-only frontend deploy for showroom gallery card polish.

- Project root: `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay`
- Frontend canister: `mprew-viaaa-aaaah-quola-cai`
- Implementation commit: `d39800bb`
- Gmai review commit/artifact: `e14f393e`, `docs/runbooks/infinity-arcade-showroom-card-hover-author-gmai-review-2026-05-14.md`

## Change

- Removed author line from the showroom gallery game card only.
- Kept details popup author/developer display intact.
- Added card hover margin, z-index, gentler lift/scale, and glow so the green border does not clip aesthetically on hover.
- Backend untouched.

## Review

Gmai verdict: `APPROVE`.

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
92a290f0a73070fa68402fb716dd08148f1d90ffd2e2baa05fe1e903631c9873
```

## Post-Deploy Verification

Live URL checked:

```text
https://mprew-viaaa-aaaah-quola-cai.raw.icp0.io/index.html
```

Verification result:

```json
{"CardAuthorRemoved":true,"DetailsAuthorKept":true,"HoverMargin":true,"HoverScale":true,"HoverZIndex":true,"Sha":"92a290f0a73070fa68402fb716dd08148f1d90ffd2e2baa05fe1e903631c9873"}
```
