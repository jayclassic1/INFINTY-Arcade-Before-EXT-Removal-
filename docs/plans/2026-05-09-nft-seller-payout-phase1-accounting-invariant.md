# NFT seller payout Phase 1 accounting invariant

Phase 1 makes the fixed economy rates explicit and testable without wiring live NFT seller payouts.

## Fixed rates

- 1 ICP = 100,000,000 e8s
- 1 ICP = 100 Tokens
- 1 ICP = 1,000 Tickets
- 1 Token = 1,000,000 e8s
- 1 Ticket = 100,000 e8s

The backend source of truth is the fixed economy constants in `backend/main.mo`:

- `ICP_E8S`
- `TOKENS_PER_ICP`
- `TICKETS_PER_ICP`
- `TOKEN_LIABILITY_E8S`
- `TICKET_LIABILITY_E8S`

## Seller payout math, not live payout wiring

The private helper `ticketCostToSellerPayoutE8s(ticketCost)` documents the future NFT seller payout conversion at the exact fixed rate:

- 100 tickets => 10,000,000 e8s
- 1000 tickets => 100,000,000 e8s

`redeemUserNft` remains payout-deferred in Phase 1. It still spends Tickets and transfers the escrowed NFT, but it does not credit seller ICP or change claim behavior.

## Query surface

`getEconomyRates()` exposes the constants and the two canonical examples so backend/frontend IDL drift is visible before deployment.

## Strategic path

Phase 2 should split claim-pipe accounting into separate buckets before seller payout wiring:

1. game creator earnings
2. NFT seller earnings
3. refunds

The claim pipe can stay hardened and shared, but the liability buckets must remain independently auditable so NFT seller earnings do not become entangled with game creator royalties or refund balances.
