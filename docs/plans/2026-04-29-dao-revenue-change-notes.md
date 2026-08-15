# DAO Revenue Change Notes — 2026-04-29

## Source
Discord #jaynolan discussion with JayNolan on 2026-04-29.

## Desired Direction
- Simplify Infinity Arcade DAO economics so the DAO does **not** broadly receive revenue from every platform revenue stream.
- DAO revenue should be tied to **gaming activity**, not NFT/listing/artist marketplace revenue.
- Keep the accounting easy to explain and easier to audit.

## Important Distinction
There are two separate ticket systems and they should not be confused:

1. **Game ticket jackpot / game ticket pools**
   - Funded by ticket-game play.
   - Used for game/player prize payouts.
   - Should stay separate from DAO rewards.

2. **DAO ticket jackpot**
   - A DAO member/community reward system.
   - May be kept because ticket rewards can stimulate NFT purchases/redemptions.
   - If NFT revenue is removed from DAO splits, this needs a non-NFT funding source.

## Confirmed Decision
Jay approved the final-product cleanup on 2026-04-29:

- DAO keeps its gameplay revenue share.
- DAO rewards are funded by the DAO’s **gaming revenue share** only.
- NFT, listing, mint, artist/seller, token-purchase, and gashapon commerce do not fund DAO rewards unless explicitly re-approved later.
- Game ticket jackpots / per-game backed ticket pools remain separate from any DAO ticket jackpot.
- Do **not** drain per-game ticket pools to fund DAO jackpots; game ticket pools should remain reserved for their game payout economy.

## Clean Policy Statement
> The DAO does not broadly share in platform revenue. DAO rewards are funded by gaming activity. Game ticket pools fund game prizes; DAO rewards pools fund DAO member jackpots; NFT and artist revenue remain separate.

## Implementation Notes
Code/copy changes investigated in this implementation pass:

- Backend revenue split constants and gameplay accounting around:
  - `TICKET_GAME_DAO_SHARE`
  - `REGULAR_GAME_DAO_SHARE`
  - `TICKET_GAME_POOL_SHARE`
- Any DAO jackpot accounting path, if present or planned.
- Frontend copy that currently implies DAO/community participation in NFT/ticket/platform fees.
- Creator dashboard copy around:
  - ticket games
  - non-ticket games
  - NFT listing/mint/redeem fees
  - DAO/community rewards

## Implementation Result
- Frontend copy should present DAO economics as **DAO gaming rewards**, not broad NFT/platform DAO revenue.
- Backend inspection found gameplay DAO split constants and ticket-game pool funding, but no NFT/listing/mint/gashapon DAO credit path to remove in this pass.
- The frontend IDL still contains legacy/stale `getRevenueSplitConfig` field names such as `userMintDaoShare` and `collectionDaoShare`; this pass leaves the interface intact because no UI copy uses those fields for final-product economics.
- No deploy is authorized by this note.

## Phase 2 Findings

### Actual accounting
- `backend/main.mo` has platform-wide revenue logging for NFT listing/mint/showroom, game submission/showroom, token purchases, and NFT redemption events.
- That revenue log feeds aggregate platform revenue stats; it is not DAO reward accounting.
- The only DAO-share constants found in canonical backend source are gameplay split constants: `TICKET_GAME_DAO_SHARE` and `REGULAR_GAME_DAO_SHARE`.
- Ticket-game pool funding is separate from DAO rewards through per-game raw/backed ticket-pool accounting.

### Stale compatibility
- `index.html` still declares a legacy `getRevenueSplitConfig` Candid surface with older names including `collectionDaoShare`, `userMintDaoShare`, `daoTreasuryShare`, and `daoNonTicketShare`.
- Those fields are preserved for compatibility only and must not be rendered as final-product DAO economics.
- DAO dashboard and admin treasury source tables now use a centralized gaming-source allowlist so non-gaming labels cannot be reintroduced in those active reward/revenue contexts by local label edits.

### No accounting mutation
- No stable backend schema or deployed canister state was changed in this local pass.
- No deploy was performed.
