Verdict: REVISE REQUIRED

Evidence checked: index.html, games/swing-blade/index.html, scripts/validate-swing-blade-input-bridge.mjs; current uncommitted diff limited to the requested source files plus this review artifact. Manual path-containment fallback performed because verify_write_scope tool was unavailable: planned write path `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks\infinity-arcade-swing-blade-passive-focus-hint-gmai-review-2026-05-14.md` resolves under allowed root `C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay\docs\runbooks`.

Tests run:
- `node scripts\validate-swing-blade-input-bridge.mjs` — PASS (36/36 checks passed)
- `node tmp\extract-html-scripts.cjs; node --check tmp\check-index.mjs; node --check tmp\check-swing-blade.mjs` — PASS; extracted 5 parent script blocks and 1 Swing Blade script block, syntax checks passed

Issues:
1. REVISE: Parent `arcade-input-ready` handling is not source-strict when the iframe is missing. In `index.html:4955-4958`, `if(!iframe||event.source===iframe.contentWindow) dismissGameFocusOverlay();` dismisses the hint if no current `#gameIframe` exists. The stated requirement is to dismiss only for the current iframe/source. This should require a live iframe and matching `event.source` before dismissing, e.g. `if(iframe && event.source===iframe.contentWindow) dismissGameFocusOverlay();`.

Positive checks:
- Parent focus hint is now a `div`, uses `pointer-events:none`, has passive copy `Click Game to activate keyboard`, and no click/pointer handlers.
- Blocking click-wall behavior was removed from the focus hint.
- Space fallback forwards only when no custom mapping already forwarded (`fallback&&!forwarded`).
- Swing Blade posts `arcade-input-ready` only after `document.activeElement === gameCanvas`.
- Existing Play/Insert Token coin gate flow was not substantively changed; diffs only remove auto-dismiss of the focus hint during launch focus attempts.
- Details/showroom behavior was not touched by the reviewed diff.
- No backend/canister/economics calls were added in the Swing Blade patch per validator and diff review.

Residual risk: Review was source-and-syntax based; no live browser interaction screenshot was captured. Main remaining risk is the source validation gap above for stale/non-current ready messages.

Next action: Revise `index.html` so `arcade-input-ready` dismisses the passive hint only when `event.source` matches the current game iframe, then rerun the validator and syntax extraction/checks.
