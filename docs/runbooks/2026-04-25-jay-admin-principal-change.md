# Jay Admin Principal Change - 2026-04-25

## Summary
Added Jay's current Internet Identity principal to the Infinity Arcade production admin allowlists:

- `fb6so-esdgb-uuuco-wjwky-qzrmj-kbljo-62sbb-vxmjq-oxwsa-d7ufn-cqe`

## Files changed
- `backend/main.mo` - added the principal to `ADMINS` while preserving existing `7uj7m`, `xcreu`, and legacy `JAY_PRINCIPAL` admin access.
- `index.html` - added the same principal to `ADMIN_PRINCIPALS` so the admin UI is visible after wallet login.

## Preserved existing production-safety changes
- `backend/main.mo` already had the Model A stable ticket pool fields moved after legacy stable fields to avoid stable field order upgrade risk; this was preserved.
- `index.html` already had active backend/vault/deposit constants changed from `x47vc-qaaaa-aaaai-radva-cai` to production backend `pifyq-raaaa-aaaab-agrqq-cai`; this was preserved.

## Verification
- `rg -n "fb6so-esdgb-uuuco-wjwky-qzrmj-kbljo-62sbb-vxmjq-oxwsa-d7ufn-cqe" backend/main.mo index.html` found the principal in both code files.
- `rg -n "4124447f786d4f994a51581bde316bd383a634f92e60df6c9b7453db16ec4206" backend/main.mo index.html` returned no matches; the deposit/account hex is absent from code.
- `rg -n "pifyq-raaaa-aaaab-agrqq-cai|x47vc-qaaaa-aaaai-radva-cai" index.html` found only `pifyq-raaaa-aaaab-agrqq-cai` matches in active frontend/backend constants.
- `git diff --check -- backend/main.mo index.html docs/runbooks/2026-04-25-jay-admin-principal-change.md` passed with no whitespace errors.
- `icp_check_motoko` against `backend/dfx.json` / `arcade_backend` passed with 0 errors and existing warnings only.

## Explicit non-actions
- No deploy performed.
- No canister snapshot, install, upgrade, token transfer, or canister mutation performed.
- The screenshot account/deposit hex was not used as a principal and was not added to code.

## Deploy safety note
After Gmai approval, deploy ownership remains with Jmai:

1. Backend requires safe upgrade to `pifyq-raaaa-aaaab-agrqq-cai`.
2. Frontend deploy should target `mprew-viaaa-aaaah-quola-cai`.
3. Re-verify admin access with Jay's Internet Identity principal after both deployments.
