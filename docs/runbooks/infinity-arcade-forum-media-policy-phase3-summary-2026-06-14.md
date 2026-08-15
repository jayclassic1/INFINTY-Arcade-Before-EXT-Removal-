# Infinity Arcade Forum Media Policy Phase 3 Summary

Date: 2026-06-14
Task: `infinity-arcade-forum-media-policy-phase3`
Project: ICP-ARCADE
Target canister: `pifyq-raaaa-aaaab-agrqq-cai`
Deploy authorized: false

## Policy implemented

- Forum posting remains text-first: thread and reply bodies are required for new backend-backed posts/replies.
- Backend now caps forum section, title, body, reply body, author, and image-reference field sizes.
- Forum images are limited to compact references only:
  - allowed: `http://`, `https://`, `ipfs://`, `ar://`, `asset:`, `/uploads/`, `/assets/`
  - rejected: inline `data:` URLs, base64 payloads, oversized image reference strings, and unsupported schemes
- Forum image posting now requires media eligibility:
  - admin, or
  - voting power greater than zero, or
  - contributor badge (`dev-contributor`, `artist-contributor`, or `gashapon-contributor`)
- Public/basic connected users can still post forum text but cannot attach images.
- Proposal/media behavior was left untouched; changes are scoped to shared forum threads/replies.

## Frontend behavior

- Forum "Add Image" controls now use compact URL/asset-reference entry instead of local file/base64 upload.
- Ineligible users see a clear message that images require Voting Power, contributor badge, or admin access.
- The legacy forum file upload handler is blocked for new forum posts so backend-backed posts do not send large inline blobs.
- Client-side guards validate image refs before backend submission and before local fallback save.
- Existing local fallback remains functional and can still render older stored image values.

## Files changed

- `backend/main.mo`
  - Added forum media eligibility checks, text/field caps, compact image-reference validation, and text-first enforcement.
- `index.html`
  - Added client-side eligibility checks, image-reference validator, media policy UI messaging, and URL/asset-reference image entry.
- `scripts/validate-shared-forums-phase2.mjs`
  - Extended static validation to cover the phase 3 media policy gates/caps.
- `package.json`
  - Added `validate:forum-media-policy` alias to the shared-forums validator.

## Verification

- `npm run validate:shared-forums-phase2` — passed
- `npm run backend:check` — passed
- `npm run test:real-icp-api-surface` — passed, 9/9
- `git diff --check -- backend/main.mo index.html scripts/validate-shared-forums-phase2.mjs package.json` — passed; only line-ending normalization warnings were printed

## Residual risks

- Frontend media eligibility depends on live badge/voting-power queries; if the backend is unavailable, contributor badge cache may allow only cached contributor holders while the backend remains the final authority.
- Old local fallback posts may still contain historical inline/base64 images; this phase blocks new forum uploads rather than migrating/deleting old local data.
- No deploy, upload, canister install/upgrade, or live mutation was performed.
