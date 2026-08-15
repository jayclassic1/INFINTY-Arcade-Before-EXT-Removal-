# Gmai Review: Back Submission Hosted Thumbnail Fix

Task: `icp-arcade-back-submission-hosted-thumbnail-gmai-review-20260614`  
Project: `ICP-ARCADE`  
Reviewed commit: `ff04bdd06ae2650a15e3c5ec0edb2687a334f386`  
Trace: `39d7d41c278848e4a28bd11010bba2ce`  
Deploy/live mutation: none performed by this review.

Verdict: APPROVE

Evidence checked:
- Diff for `ff04bdd06ae2650a15e3c5ec0edb2687a334f386` covering `index.html`, `.deploy/frontend-public/index.html`, `scripts/validate-back-submission-hosted-thumbnail-flow.mjs`, and `docs/runbooks/infinity-arcade-back-submission-hosted-thumbnail-fix.md`.
- Source inspection of submission functions in `index.html`:
  - `handleSubmissionThumbUpload` now uploads through `uploadImageFileToGameAssets(file, 'hosted-submission-thumbnail')`, writes only the returned hosted URL to the hidden field, and no longer assigns `dataUrl` to the submitted thumbnail value.
  - Local preview uses `URL.createObjectURL(file)` and revokes it in `finally`, preserving immediate preview without submitting base64.
  - `assertSafeHostedThumbnailForSubmission` blocks `data:image/...` thumbnail payloads with user-safe copy.
  - Token/showroom submissions call the guard before `arcadeConfirm` and before `getBackendActor(true)` / `submitGame`.
  - Back ICP-payment submissions call the guard before `getBackendActor(true)` / `submitGameWithPayment`.
- Markup inspection confirmed both Back and Showroom thumbnail file inputs still route to `handleSubmissionThumbUpload`, preserving the shared showroom/admin submission flow behavior.
- Artifact sync checked: `.deploy/frontend-public/index.html` matches root `index.html` by validator hash.
- `git diff --exit-code -- index.html .deploy/frontend-public/index.html scripts/validate-back-submission-hosted-thumbnail-flow.mjs docs/runbooks/infinity-arcade-back-submission-hosted-thumbnail-fix.md` returned clean, so review did not alter the implementation files.

Tests run:
- `node scripts\validate-back-submission-hosted-thumbnail-flow.mjs` — PASS (`Back submission hosted thumbnail flow validator passed`).
- `node scripts\validate-upload-ui-soft-audit.mjs` — PASS (`upload UI soft-audit validator passed`).
- `node scripts\validate-frontend-deploy-artifact-sync.mjs` — PASS (root/deploy SHA both `ad2a877d927d06c350d1934f42be746a9480b251cb9b5584dcbd96892febaffa`).
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai` — PASS; verified frontend canister config and sanitized 36 payload files.

Issues:
- None blocking.

Residual risk:
- The browser upload path now depends on the connected identity having game asset canister upload permissions. If the wallet lacks permissions, submission is blocked before payment/backend submission with hosted-thumbnail-upload error copy; that is acceptable for this fix.
- This review did not execute an end-to-end live browser upload/payment flow and did not perform any live canister mutation or deploy.

Next action:
- Ship after normal release approval/deploy gating. Do not treat this review as deploy authorization.
