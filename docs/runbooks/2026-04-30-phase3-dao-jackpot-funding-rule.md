# Phase 3 DAO Jackpot Funding Rule

## Rule

DAO jackpot/reward pool is game-earned only. It is funded only by qualifying gameplay revenue from eligible paid games.

DAO dashboard and jackpot copy should describe the pool as game-earned, gameplay-funded, or gaming-funded. Do not describe general platform revenue as DAO jackpot/member reward funding unless Jay explicitly changes the rule later.

## Hard exclusions

The following sources must not route to or be described as DAO jackpot/member reward funding:

- NFT mint fees
- NFT listing, showroom, and application fees
- creator payouts, royalties, and seller proceeds
- deposits, token credits, and admin credits
- refunds and withdrawals
- treasury movements and sweeps
- non-game platform fees

## Accounting caveat

Preserve platform-wide audit logs for non-game revenue. The backend revenue log and total revenue counters are useful accounting history, but they are not DAO reward accounting and should not be rendered as DAO jackpot/member reward funding.

## Active source labels

The frontend DAO dashboard/admin reward source tables are intentionally allowlisted to gameplay labels only:

- `gameplay`
- `game-purchase`
- `game-demo`

If a future product decision adds a funding source, update the rule, copy, backend comments, and `scripts/validate-dao-jackpot-funding-rule.mjs` in the same commit.

## Validation

Run before review or deploy packaging:

```bash
npm run validate:dao-jackpot-funding-rule
node scripts/test-frontend-publish.mjs
```

If the deploy payload is rebuilt with `node scripts/build-frontend-publish.mjs`, rerun both checks so `.deploy/frontend-public/index.html` stays synchronized with the canonical `index.html` copy.
