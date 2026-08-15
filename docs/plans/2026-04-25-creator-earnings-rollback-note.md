# Creator Earnings Pivot Rollback Note

Pre-pivot snapshot tag: `icp-arcade-pre-creator-earnings-pivot-20260425`
Snapshot commit: `e0dbe4088fe6a4b9bb770ccb92300bbf72895a12` (`Add Jay admin principal to Infinity Arcade`)
Created: 2026-04-25

Purpose: easy source rollback before switching Infinity Arcade from automatic/timed royalty language toward claimable creator earnings.

## Important

No deploy happened when this tag was created. It is a source-code rollback point only.
Active production canisters remain:
- Frontend: `mprew-viaaa-aaaah-quola-cai`
- Backend: `pifyq-raaaa-aaaab-agrqq-cai`

## Safe rollback options

### Inspect differences

```powershell
git diff icp-arcade-pre-creator-earnings-pivot-20260425 -- workspaces/jmai/dapps/infinity-arcade-Jay
```

### Restore only the creator-earnings pivot files from pre-pivot state

Use this if we want to undo the pivot edits but keep unrelated current work:

```powershell
git checkout icp-arcade-pre-creator-earnings-pivot-20260425 -- `
  workspaces/jmai/dapps/infinity-arcade-Jay/index.html `
  workspaces/jmai/dapps/infinity-arcade-Jay/manifesto.txt
```

If the validation script/plan files should also be removed after rollback, delete these untracked pivot artifacts manually:

```powershell
Remove-Item workspaces/jmai/dapps/infinity-arcade-Jay/scripts/validate-creator-earnings-phase1.mjs -ErrorAction SilentlyContinue
Remove-Item workspaces/jmai/dapps/infinity-arcade-Jay/docs/plans/2026-04-25-creator-earnings-pivot-phases.md -ErrorAction SilentlyContinue
Remove-Item workspaces/jmai/dapps/infinity-arcade-Jay/docs/plans/2026-04-25-creator-earnings-phase1-evidence.md -ErrorAction SilentlyContinue
```

### Full repo reset to pre-pivot snapshot

Only use with explicit approval because it discards later committed source changes:

```powershell
git reset --hard icp-arcade-pre-creator-earnings-pivot-20260425
```

## Deployment rollback

Because no deploy happened yet, no canister rollback is currently needed. If a future deploy happens and needs rollback, redeploy the frontend from this snapshot/source state to `mprew-viaaa-aaaah-quola-cai`, and only mutate backend `pifyq-raaaa-aaaab-agrqq-cai` after separate preflight/review.
