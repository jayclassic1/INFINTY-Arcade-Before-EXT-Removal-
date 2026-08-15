#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const backend = readFileSync('backend/main.mo', 'utf8');
const frontend = readFileSync('index.html', 'utf8');
const deployFrontend = readFileSync('.deploy/frontend-public/index.html', 'utf8');

function extractFunction(source, name) {
  const start = source.search(new RegExp(`public\\s+shared(?:\\([^)]*\\))?\\s+func\\s+${name}\\s*\\(`));
  assert.notEqual(start, -1, `${name} must exist as a backend shared read method`);
  let depth = 0;
  let seenOpen = false;
  for (let i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] === '{') { depth++; seenOpen = true; }
    if (source[i] === '}') depth--;
    if (seenOpen && depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const snapshotType = /type\s+TreasuryLaneSnapshot\s*=\s*{[\s\S]*protectedAccountId\s*:\s*Text[\s\S]*operatingAccountId\s*:\s*Text[\s\S]*protectedBalanceE8s\s*:\s*Nat[\s\S]*operatingBalanceE8s\s*:\s*Nat[\s\S]*backendSafeWithdrawableE8s\s*:\s*Nat[\s\S]*protectedReservedE8s\s*:\s*Nat[\s\S]*operatingIncludedInBacking\s*:\s*Bool[\s\S]*operatingIncludedInBackendSafeMath\s*:\s*Bool/s;
assert.match(backend, snapshotType, 'backend must define TreasuryLaneSnapshot with protected/operating fields and false inclusion flags');

const fn = extractFunction(backend, 'getTreasuryLaneSnapshot');
assert.match(fn, /let\s+treasury\s*=\s*await\s+getTreasuryBalance\(\)/, 'lane snapshot must reuse getTreasuryBalance for protected balance and safe math');
assert.match(fn, /protectedBalanceE8s\s*=\s*treasury\.balanceE8s/, 'protected balance must mirror getTreasuryBalance().balanceE8s');
assert.match(fn, /backendSafeWithdrawableE8s\s*=\s*treasury\.withdrawableE8s/, 'safe withdrawable must mirror getTreasuryBalance().withdrawableE8s');
assert.match(fn, /protectedReservedE8s\s*=\s*treasury\.reservedE8s/, 'protected reserved must mirror getTreasuryBalance().reservedE8s');
assert.match(fn, /operatingBalanceE8s\s*=\s*await\s+ICP_LEDGER_ICRC1\.icrc1_balance_of\(\{\s*owner\s*=\s*selfPrincipal\s*;\s*subaccount\s*=\s*\?OPERATING_TREASURY_SUBACCOUNT\s*\}\)/s, 'operating balance must be an actual ICRC-1 balance of the operating subaccount');
assert.match(fn, /operatingIncludedInBacking\s*=\s*false/, 'operating must not be flagged as backing');
assert.match(fn, /operatingIncludedInBackendSafeMath\s*=\s*false/, 'operating must not be flagged as backend-safe math input');

const treasuryBalanceFn = extractFunction(backend, 'getTreasuryBalance');
assert.match(treasuryBalanceFn, /icrc1_balance_of\(\{\s*owner\s*=\s*selfPrincipal\s*;\s*subaccount\s*=\s*null\s*\}\)/s, 'getTreasuryBalance must remain main/protected account only');
assert.doesNotMatch(treasuryBalanceFn, /OPERATING_TREASURY_SUBACCOUNT|operatingBalanceE8s|operatingIncludedIn/s, 'getTreasuryBalance must not include operating treasury lane');

for (const [name, source] of [['index.html', frontend], ['.deploy/frontend-public/index.html', deployFrontend]]) {
  assert.match(source, /getTreasuryLaneSnapshot\s*:\s*IDL\.Func\(\[\],\[IDL\.Record\(\{[\s\S]*protectedAccountId\s*:\s*IDL\.Text[\s\S]*operatingAccountId\s*:\s*IDL\.Text[\s\S]*protectedBalanceE8s\s*:\s*IDL\.Nat[\s\S]*operatingBalanceE8s\s*:\s*IDL\.Nat[\s\S]*backendSafeWithdrawableE8s\s*:\s*IDL\.Nat[\s\S]*protectedReservedE8s\s*:\s*IDL\.Nat[\s\S]*operatingIncludedInBacking\s*:\s*IDL\.Bool[\s\S]*operatingIncludedInBackendSafeMath\s*:\s*IDL\.Bool/s, `${name}: frontend IDL must expose getTreasuryLaneSnapshot`);
}

console.log('treasury lane snapshot validation passed');
