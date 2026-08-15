# Operating Treasury Lanes — Phase 3 Withdraw

## Scope

Local implementation only. No deploy, upgrade, canister mutation, live admin call, or fund movement is authorized by this phase.

## Behavior

- Adds `adminWithdrawOperatingTreasury(destination, amountE8s)` for admin-only ICP withdrawals from the backend-owned Operating Treasury subaccount.
- Keeps `adminWithdrawTreasury(toPrincipal, amountE8s)` as a legacy admin-panel wrapper that routes to a principal main account through the same Operating Treasury implementation.
- Defines `amountE8s` as the net transfer amount. The Operating Treasury subaccount must also have enough ICP to pay the ledger fee.
- Reads the Operating Treasury balance before transfer and rejects if `amountE8s + ICP_LEDGER_FEE_E8S` exceeds that balance.

## Safety

- Draw source is always `from_subaccount = ?OPERATING_TREASURY_SUBACCOUNT`.
- The protected/main treasury account is never used as the source for this method.
- `getTreasuryBalance()` remains protected/main-only and does not include Operating Treasury balances.
- Protected/backing reserves, token liabilities, ticket liabilities, creator/seller earnings, refunds, and safety buffer are not consulted or reduced by the Operating Treasury withdrawal path.
- A transient in-flight lock rejects overlapping Operating Treasury withdrawals and is cleared on success, ledger error, balance rejection, or trap.
- Zero and dust amounts at or below the ICP ledger fee are rejected.
- Ledger failures return Result-style text errors instead of trapping.

## Frontend/admin surface

- Admin UI copy now labels this as **Operating Treasury Withdrawal** and states it is separate from Protected / Backing controls.
- The new IDL method uses an Account-shaped destination (`owner`, optional `subaccount`).
- Phase 3 UI enables principal destinations through `adminWithdrawOperatingTreasury({ owner, subaccount: [] }, amountE8s)` and leaves raw account-id withdrawals disabled until a safe account-id shape is added.

## Deploy gate

Before any future deploy or live use:

1. Gmai review must approve the implementation and validator coverage.
2. Run all required local gates from the task evidence.
3. Perform identity/canister preflight for the target canister.
4. Confirm the live backend candid surface includes `adminWithdrawOperatingTreasury`.
5. Require explicit human approval for any live admin withdrawal call or fund movement.
