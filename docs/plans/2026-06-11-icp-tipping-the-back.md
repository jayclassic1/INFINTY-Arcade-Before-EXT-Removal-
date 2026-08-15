# ICP Tipping for The Back Implementation Plan

> **For execution:** Use the subagent-driven-development skill to implement this plan. Route each task by its ownership tag.

**Goal:** Add anonymous-by-default direct ICP tipping for game creators who post games in The Back.

**Architecture:** ICP tips are non-custodial: the frontend sends ICP directly from the connected user wallet to the creator principal/account already stored on each game submission. The backend records display-only tip receipts after transfer success so The Back can show totals and recent support without becoming a custodian or payout ledger.

**Tech Stack:** Motoko backend (`backend/main.mo`), single-file frontend (`index.html`), ICP ledger ICRC-1 transfer via existing `getLedgerActor(true)`, existing frontend publish/build scripts, backend Motoko build/tests.

---

## Scope and Safety

- No deploy in this implementation phase. Jmai must ask again before any upload/backend upgrade.
- No new canisters.
- No raw DFX.
- No controller, cycles, identity, or secret changes.
- ICP moves directly from tipper wallet to creator principal/account.
- Backend receipt is display/audit state only, not custody and not creator cashout accounting.
- Tips are anonymous in UI by default; user may opt in to show profile name.

## Safe backend deploy-lane preparation

Project-local readiness now uses the reusable manager `scripts/prepare-infinity-arcade-upgrade.mjs`; `scripts/prepare-jay-backend-upgrade-lane.mjs` remains as a compatibility wrapper. The manager is bound to Jay's active Infinity Arcade root, backend canister `pifyq-raaaa-aaaab-agrqq-cai`, frontend canister `mprew-viaaa-aaaah-quola-cai`, network `ic`, and operation `backend_upgrade` only.

The manager intentionally reads fresh ICP toolchain artifacts from `.build` only:

- `backend/.build/arcade_backend.wasm`
- `backend/.build/arcade_backend.did`

It recomputes WASM/DID SHA-256 hashes on each run, verifies the `.build` artifact timestamps are newer than or equal to the latest relevant backend source timestamp, and verifies the candidate DID exposes `recordIcpTip`, `getGameIcpTipSummary`, and `getRecentGameIcpTips`. Stale `.dfx` artifacts are not candidate inputs.

Generate the readiness packet after a safe local backend build:

```powershell
npm run backend:build
node scripts/prepare-infinity-arcade-upgrade.mjs --artifactDir=C:\Users\Jesse\OpenClawEvidence\icp-arcade-icp-tipping
```

The packet is compatible with the repo-global generic existing-backend lane by carrying the mapping to `GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER`, but it remains readiness-only with `mutationAllowedNow: false` until governed runtime-provider safe-wrapper proof exists. The packet includes candidate hashes, required methods present/missing, source/artifact timestamps, stable migration/test checklist, pre-upgrade state proof requirements, rollback placeholders, and post-verify placeholders.

Regression coverage:

```powershell
node scripts/test-infinity-arcade-upgrade-manager.mjs
node scripts/test-jay-backend-upgrade-lane.mjs
```

Next live-safe route remains backend-first then frontend-second:
1. Use the readiness artifact as an approval packet input only; this script performs no mutation and must not authorize execution.
2. A separately approved governed safe-wrapper runner must upgrade only backend `pifyq-raaaa-aaaab-agrqq-cai` from the exact candidate WASM after review.
3. Post-verify the certified backend module hash equals the candidate hash and the method surface includes `recordIcpTip`, `getGameIcpTipSummary`, and `getRecentGameIcpTips`.
4. Only after backend verification, allow any separately authorized frontend-only manifest for `mprew-viaaa-aaaah-quola-cai`.

Reusable process details are documented in `docs/runbooks/infinity-arcade-upgrade-manager.md`.

## Task 1: [IAMJ] Add backend receipt model and query/update methods

**Files:**
- Modify: `backend/main.mo`
- Test/update if needed: existing backend test harness files under `backend/` or `scripts/`

**Step 1: Add a stable receipt type**

Add a `TipReceipt` record with fields similar to:

```motoko
type TipReceipt = {
  id : Text;
  gameId : Text;
  creator : Principal;
  tipper : Principal;
  amountE8s : Nat;
  anonymous : Bool;
  displayName : Text;
  txRef : Text;
  createdAt : Int;
};
```

Use stable entries and transient map/buffer patterns consistent with existing game/NFT storage.

**Step 2: Add receipt recording method**

Add an update method:

```motoko
public shared({ caller }) func recordIcpTip(
  gameId : Text,
  creator : Principal,
  amountE8s : Nat,
  anonymous : Bool,
  displayName : Text,
  txRef : Text
) : async { #ok : Text; #err : Text }
```

Validation:
- `caller` must not be anonymous.
- `gameId` must identify an existing game submission.
- `creator` must match that game submission's `creator`.
- `amountE8s` must be >= minimum display threshold, recommended `10_000` e8s (0.0001 ICP) or higher if current UI chooses.
- Store `displayName` only when `anonymous == false`; otherwise store empty display name.
- Store `txRef` as display/audit text only.

**Step 3: Add query methods**

Add queries:

```motoko
public query func getGameIcpTipSummary(gameId : Text) : async { totalE8s : Nat; count : Nat }
public query func getRecentGameIcpTips(gameId : Text, limit : Nat) : async [TipReceipt]
```

Return anonymous receipts with `tipper` hidden only if the existing Candid type allows; if not, frontend must ignore/show anonymous based on the `anonymous` flag. Do not expose private data beyond public principals already in game submissions.

**Step 4: Run backend gates**

Run:

```powershell
npm run backend:build
node scripts/validate-real-icp-api-surface.mjs
node scripts/validate-dao-jackpot-funding-rule.mjs
python backend/test_postupgrade_migration_safety.py
python backend/test_admin_game_upload_registration_static.py
```

Expected: all pass. If a new test is added for tips, include it in this gate.

## Task 2: [IAMJ] Add frontend tip modal and direct ICP transfer

**Files:**
- Modify: `index.html`
- Test: create/update frontend test script under `scripts/` if feasible.

**Step 1: Add amount helpers**

Add helpers near existing ICP ledger/wallet helpers:

```js
const ICP_TIP_FEE_E8S = 10000n;
const ICP_TIP_MIN_E8S = 10000n;
function icpToE8sInput(value){ /* parse decimal ICP safely */ }
function formatIcpAmount(e8s){ return e8sToIcp(BigInt(e8s||0)); }
```

Do not use floating-point math for final transfer amount; parse decimal string into e8s.

**Step 2: Add Tip ICP UI on The Back game cards/details**

Add a compact button to Backroom/The Back cards and/or game detail modal:

```html
<button class="btn" onclick="openIcpTipModal('<gameId>')">Tip ICP</button>
```

Only show when creator principal is present. If the viewer is the creator, either hide or disable with “You created this game.”

**Step 3: Add tip modal**

Modal content:
- Creator/game name.
- Preset buttons: `0.05`, `0.1`, `0.5` ICP.
- Custom amount input.
- Default checked: anonymous.
- Optional unchecked/checkbox: “Show my arcade name as supporter.”
- Warning: “ICP is sent directly to the creator wallet. On-chain transactions are public even if arcade display is anonymous.”
- Confirm button.

**Step 4: Send ICP directly to creator**

Use existing ledger actor with identity:

```js
const ledger = await getLedgerActor(true);
const result = await ledger.icrc1_transfer({
  to: { owner: Principal.fromText(creatorPrincipalText), subaccount: [] },
  fee: [ICP_TIP_FEE_E8S],
  memo: [],
  from_subaccount: [],
  created_at_time: [],
  amount: amountE8s,
});
```

Handle `Ok` as transaction/block reference. Handle `Err` with safe user-facing messages.

**Step 5: Record display receipt after successful transfer**

Call backend `recordIcpTip(...)` only after successful transfer. If receipt recording fails after transfer, show transfer success and a non-blocking “display receipt could not be saved” message.

## Task 3: [IAMJ] Render tip totals/recent anonymous support

**Files:**
- Modify: `index.html`

**Step 1: Add summary hydration**

After Backroom/The Back games render, query tip summary for visible games and hydrate slots:

```js
getGameIcpTipSummary(game.id)
```

Display: `∞ 0.25 ICP tipped` or hide when zero.

**Step 2: Add recent support display**

In the game detail modal, show recent tips:
- Anonymous: `Anonymous supporter tipped 0.1 ICP`
- Non-anonymous: `<name> tipped 0.1 ICP`

No public tipper principal in the UI by default.

## Task 4: [IAMJ] Tests and build artifacts

**Files:**
- Create/modify: `scripts/test-icp-tip-ui-contract.mjs` or similar
- Rebuild: `.deploy/frontend-public/index.html` via existing frontend build script

**Step 1: Add frontend static regression**

Test that:
- Tip modal defaults to anonymous.
- Ledger transfer points to `game.creator` principal, not backend/treasury.
- Receipt recording happens after transfer success.
- Warning text says on-chain transactions are public.

**Step 2: Run gates**

Run:

```powershell
node scripts/test-icp-tip-ui-contract.mjs
node scripts/test-frontend-publish.mjs
node scripts/build-frontend-publish.mjs
npm run backend:build
node scripts/validate-real-icp-api-surface.mjs
python backend/test_postupgrade_migration_safety.py
```

Expected: all pass.

**Step 3: Commit**

Commit explicit paths only:

```powershell
git add backend/main.mo index.html scripts/test-icp-tip-ui-contract.mjs .deploy/frontend-public/index.html
 git commit -m "Add anonymous ICP tipping for The Back"
```

## Task 5: [GMAI] Review gate

**Files:**
- Review all changed project files.

**Review criteria:**
- No custody introduced.
- ICP recipient is creator principal/account.
- Anonymous default is UI default.
- Backend receipt cannot fabricate tip totals before a transfer path in frontend.
- Backend stable upgrade safety is preserved.
- No deploy approval implied.

Return proof line:

```text
REVIEW_VERDICT status=APPROVE evidence=<files/tests> tests=<tests> risk=<residual-risk>
```

## Task 6: [JMAI] Deployment approval packet only

**Success criteria:**
- Jmai reports local implementation commit, tests, and Gmai verdict.
- Jmai asks for separate explicit approval before any frontend upload or backend upgrade.
- Approval packet must name target frontend `mprew-viaaa-aaaah-quola-cai`, backend `pifyq-raaaa-aaaab-agrqq-cai`, commit, artifact manifest, and state no new canister/raw DFX/controller/cycles/identity changes.
