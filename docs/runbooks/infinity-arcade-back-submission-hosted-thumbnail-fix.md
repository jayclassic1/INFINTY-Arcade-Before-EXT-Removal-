# Infinity Arcade Back Submission Hosted Thumbnail Fix

Task: `icp-arcade-back-submission-hosted-thumbnail-fix-20260614`  
Trace: `ec9fac085b70437b9489cddde129a49d`  
Project: ICP-ARCADE / Infinity Arcade Jay  
Target canisters: frontend `mprew-viaaa-aaaah-quola-cai`; backend `pifyq-raaaa-aaaab-agrqq-cai` (reference only)  
Deploy/live mutation: none.

## Summary

Implemented the approved frontend-only hosted-thumbnail fix for The Back/Showroom submission flow.

- `handleSubmissionThumbUpload` now uploads selected submission thumbnails through the existing `uploadImageFileToGameAssets` asset-canister upload helper using scope `hosted-submission-thumbnail`.
- The hidden submission thumbnail value is now the hosted URL returned by the upload helper, not an optimized `data:image/...;base64,...` payload.
- The preview still appears immediately using a local `URL.createObjectURL(file)` while the hosted upload is pending, then swaps to the hosted URL when ready.
- Added `assertSafeHostedThumbnailForSubmission` to block `data:image/...` thumbnail payloads before fee confirmation/payment/backend submit.
- The Back ICP-payment branch now runs the same guard before `submitGameWithPayment`; token/showroom submissions run the guard through `submitGamePayload` before `arcadeConfirm` and before `submitGame`.
- Error copy now uses hosted-thumbnail-upload language so users see upload/hosting failure separately from backend submission failure.

## Files changed

- `index.html`
- `.deploy/frontend-public/index.html`
- `scripts/validate-back-submission-hosted-thumbnail-flow.mjs`
- `docs/runbooks/infinity-arcade-back-submission-hosted-thumbnail-fix.md`

## Verification

Red/green TDD evidence:

1. Initial focused validator failed before implementation:
   - Command: `node scripts\\validate-back-submission-hosted-thumbnail-flow.mjs`
   - Expected failure: `submission thumbnail helper must upload to hosted game assets before setting hidden thumbnail value`

Passing verification after implementation:

```text
node scripts\\validate-back-submission-hosted-thumbnail-flow.mjs
Back submission hosted thumbnail flow validator passed

node scripts\\validate-upload-ui-soft-audit.mjs
upload UI soft-audit validator passed

node scripts\\validate-frontend-deploy-artifact-sync.mjs
root index.html sha256: ad2a877d927d06c350d1934f42be746a9480b251cb9b5584dcbd96892febaffa
deploy .deploy/frontend-public/index.html sha256: ad2a877d927d06c350d1934f42be746a9480b251cb9b5584dcbd96892febaffa
PASS deploy artifact index.html matches reviewed root index.html

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai
Predeploy check passed. Verified frontendCanister=mprew-viaaa-aaaah-quola-cai and frontendDeploySource=C:\\Users\\Jesse\\.openclaw\\workspaces\\jmai\\dapps\\infinity-arcade-Jay\\.deploy\\frontend-public.
Sanitized payload files: 36
```

## Residual risk

No backend/IDL changes were made. The submission path now depends on the connected wallet having asset upload permission for the configured game asset canister; if it lacks permission, submission is blocked before charge/submit with sanitized hosted-thumbnail-upload copy.
