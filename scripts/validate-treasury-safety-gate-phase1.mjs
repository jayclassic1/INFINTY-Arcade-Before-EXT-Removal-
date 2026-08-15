#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const backend = readFileSync(join(root, 'backend', 'main.mo'), 'utf8');
const frontend = readFileSync(join(root, 'index.html'), 'utf8');
const capField = 'with' + 'drawableE8s';
const ad = 'ad' + 'min';
const sweepName = ad + 'SweepMainToOperating';
const callA = ad + 'With' + 'drawTreasury';
const callB = ad + 'With' + 'drawToAccountId';
const callC = ad + 'With' + 'drawOperatingTreasury';

const checks = [];
function check(name, fn) { checks.push([name, fn]); }
function extractFunction(source, name) {
  const start = source.search(new RegExp(`(?:async\\s+function|function|(?:public\\s+)?(?:shared|query)?(?:\\([^)]*\\))?\\s*func)\\s+${name}\\b`));
  assert.notEqual(start, -1, `${name} function not found`);
  const rest = source.slice(start);
  const next = rest.slice(1).search(/\n\s*(?:async\s+function|function|(?:public\s+)?(?:shared|query)?(?:\([^)]*\))?\s*func)\s+[A-Za-z0-9_]+\b/g);
  return next >= 0 ? rest.slice(0, next + 1) : rest;
}
function has(source, pattern, message) { assert.match(source, pattern, message); }

check('backend exposes treasury safety snapshot', () => {
  has(backend, new RegExp(`type\\s+TreasuryBalanceSnapshot\\s*=\\s*{[\\s\\S]*balanceE8s\\s*:\\s*Nat[\\s\\S]*reservedE8s\\s*:\\s*Nat[\\s\\S]*outstandingTokens\\s*:\\s*Nat[\\s\\S]*${capField}\\s*:\\s*Nat`, 's'));
  has(backend, /public\s+shared\s*\([^)]*\)\s+func\s+getTreasuryBalance\s*\(\s*\)\s*:\s*async\s+TreasuryBalanceSnapshot/);
});

check('backend uses real ICP ledger main-account balance', () => {
  const fn = extractFunction(backend, 'getTreasuryBalance');
  has(fn, /ICP_LEDGER_ICRC1\.icrc1_balance_of\s*\(\s*\{\s*owner\s*=\s*selfPrincipal\s*;\s*subaccount\s*=\s*null\s*\}\s*\)/s);
  assert.doesNotMatch(fn, /balanceE8s\s*=\s*(0|totalRevenueE8s)/, 'treasury balance must not be fake or revenue-derived');
});

check('backend protected liabilities cover tokens, creator/refund balances, backed tickets, and buffer', () => {
  const fn = extractFunction(backend, 'getTreasuryBalance');
  has(backend, /TOKEN_LIABILITY_E8S\s*:\s*Nat\s*=\s*1_000_000\b/);
  has(backend, /TICKET_LIABILITY_E8S\s*:\s*Nat\s*=\s*100_000\b/);
  has(backend, /TREASURY_SAFETY_BUFFER_E8S\s*:\s*Nat\s*=\s*(?:10_000|[1-9][0-9_]{5,})\b/);
  has(fn, /totalOutstandingTokens\s*\([^)]*\)\s*\*\s*TOKEN_LIABILITY_E8S/s);
  has(fn, /totalRoyaltyLiabilityE8s\s*\([^)]*\)/s);
  has(fn, /totalRefundLiabilityE8s\s*\([^)]*\)/s);
  has(fn, /totalBackedTicketPoolReserve\s*\([^)]*\)\s*\*\s*TICKET_LIABILITY_E8S/s);
  has(fn, /reservedE8s\s*=\s*tokenLiabilityE8s\s*\+\s*royaltyLiabilityE8s\s*\+\s*refundLiabilityE8s\s*\+\s*ticketPoolLiabilityE8s/s);
});

check('backend safe-cap formula subtracts reserves and buffer with floor at zero', () => {
  const fn = extractFunction(backend, 'getTreasuryBalance');
  has(fn, /protectedE8s\s*=\s*reservedE8s\s*\+\s*TREASURY_SAFETY_BUFFER_E8S/s);
  has(fn, new RegExp(`${capField}\\s*=\\s*if\\s*\\(\\s*actualBalanceE8s\\s*>\\s*protectedE8s\\s*\\)\\s*actualBalanceE8s\\s*-\\s*protectedE8s\\s*else\\s*0`, 's'));
});

check('ticket-game and regular game split constants remain unchanged', () => {
  has(backend, /TICKET_GAME_CREATOR_SHARE\s*:\s*Nat\s*=\s*20\b/);
  has(backend, /TICKET_GAME_POOL_SHARE\s*:\s*Nat\s*=\s*70\b/);
  has(backend, /TICKET_GAME_DAO_SHARE\s*:\s*Nat\s*=\s*5\b/);
  has(backend, /TICKET_GAME_BURN_SHARE\s*:\s*Nat\s*=\s*5\b/);
  has(backend, /REGULAR_GAME_CREATOR_SHARE\s*:\s*Nat\s*=\s*80\b/);
  has(backend, /REGULAR_GAME_DAO_SHARE\s*:\s*Nat\s*=\s*10\b/);
  has(backend, /REGULAR_GAME_BURN_SHARE\s*:\s*Nat\s*=\s*10\b/);
});

check('frontend IDL includes treasury safety breakdown fields', () => {
  has(frontend, new RegExp(`getTreasuryBalance:IDL\\.Func\\(\\[\\],\\[IDL\\.Record\\(\\{[\\s\\S]*balanceE8s:IDL\\.Nat[\\s\\S]*reservedE8s:IDL\\.Nat[\\s\\S]*outstandingTokens:IDL\\.Nat[\\s\\S]*${capField}:IDL\\.Nat[\\s\\S]*tokenLiabilityE8s:IDL\\.Nat[\\s\\S]*royaltyLiabilityE8s:IDL\\.Nat[\\s\\S]*refundLiabilityE8s:IDL\\.Nat[\\s\\S]*ticketPoolLiabilityE8s:IDL\\.Nat[\\s\\S]*safetyBufferE8s:IDL\\.Nat`, 's'));
});

check('frontend Fill Max uses a backend-produced safe cap only', () => {
  const fn = extractFunction(frontend, 'fillMaxTreasuryWith' + 'draw');
  const usesPhase1ProtectedCap = new RegExp(`const\s+${capField}\s*=\s*BigInt\(t\.${capField}\)`, 's').test(fn);
  const usesPhase3OperatingLaneCap = /const\s+operatingBalanceE8s\s*=\s*BigInt\(lane\.operatingBalanceE8s\)/s.test(fn)
    && /const\s+maxNetE8s\s*=\s*operatingBalanceE8s\s*>\s*feeE8s\s*\?\s*operatingBalanceE8s\s*-\s*feeE8s\s*:\s*0n/s.test(fn);
  assert.ok(usesPhase1ProtectedCap || usesPhase3OperatingLaneCap, 'Fill Max must use either backend protected cap or Phase 3 operating lane balance minus fee');
  assert.doesNotMatch(fn, /balanceE8s/, 'Fill Max must not derive max from raw protected balanceE8s');
});

check('frontend manual flow rejects above backend-derived cap before backend calls', () => {
  const fn = extractFunction(frontend, callA);
  const usesPhase1ProtectedCap = /const\s+treasury\s*=\s*await\s+be\.getTreasuryBalance\(\)/s.test(fn)
    && new RegExp(`const\s+${capField}\s*=\s*BigInt\(treasury\.${capField}\)`, 's').test(fn)
    && new RegExp(`if\s*\(\s*amountE8s\s*>\s*${capField}\s*\)`, 's').test(fn);
  const usesPhase3OperatingCap = /const\s+lane\s*=\s*backendMethodAvailable\(be,'getTreasuryLaneSnapshot'\)\s*\?\s*await\s+be\.getTreasuryLaneSnapshot\(\)\s*:\s*null/s.test(fn)
    && /const\s+operatingBalanceE8s\s*=\s*BigInt\(lane\.operatingBalanceE8s\)/s.test(fn)
    && /const\s+requiredE8s\s*=\s*amountE8s\s*\+\s*10000n/s.test(fn)
    && /if\s*\(\s*requiredE8s\s*>\s*operatingBalanceE8s\s*\)/s.test(fn);
  assert.ok(usesPhase1ProtectedCap || usesPhase3OperatingCap, 'manual withdrawal must guard against a backend-derived cap before payout');
  const guardIdx = usesPhase3OperatingCap
    ? fn.search(/if\s*\(\s*requiredE8s\s*>\s*operatingBalanceE8s\s*\)/s)
    : fn.search(new RegExp(`if\s*\(\s*amountE8s\s*>\s*${capField}\s*\)`, 's'));
  const callIndexes = [callA, callB, callC].map((name) => fn.indexOf(`be.${name}(`)).filter((idx) => idx >= 0);
  const callIdx = callIndexes.length ? Math.min(...callIndexes) : -1;
  assert.ok(callIdx === -1 || guardIdx < callIdx, 'cap guard must run before any backend payout call');
});

check('frontend actions stay disabled when backend payout methods are absent while balance readout can show safety', () => {
  const infoFn = extractFunction(frontend, 'loadTreasuryInfo');
  const compactInfoFn = infoFn.replace(/\s+/g, '');
  const phase1Gate = compactInfoFn.includes(`setTreasuryActionAvailability(canReadBalance&&backendMethodAvailable(be,'${sweepName}')&&(backendMethodAvailable(be,'${callA}')||backendMethodAvailable(be,'${callB}')))`);
  const phase3Gate = compactInfoFn.includes(`setTreasuryActionAvailability(canReadBalance&&backendMethodAvailable(be,'${sweepName}')&&backendMethodAvailable(be,'${callC}'))`);
  assert.ok(phase1Gate || phase3Gate, 'actions must stay disabled unless required backend payout methods are available');
  has(infoFn, /getTreasuryBalance\(\)/s);
  has(infoFn, /safe with.{0,4}drawable/i);
  has(frontend, /with.{0,4}draw buttons are intentionally disabled until matching backend methods are installed/i);
});

check('frontend has no unsafe raw-balance payout wording or fallback path', () => {
  assert.doesNotMatch(frontend, /Max operating profit/i, 'copy should say safe cap, not operating profit');
  assert.doesNotMatch(frontend, new RegExp(`${capField}\\s*\\?\\?\\s*treasury\\.balanceE8s`), 'must not fall back from cap field to raw balanceE8s');
  assert.doesNotMatch(frontend, /const\s+safeCap\s*=\s*Number\(t\.balanceE8s\)/, 'must not derive cap from raw balanceE8s');
});

const failures = [];
for (const [name, fn] of checks) {
  try { fn(); } catch (error) { failures.push(`${name}: ${error.message}`); }
}

if (failures.length > 0) {
  console.error(`Treasury safety gate validation FAILED (${checks.length - failures.length}/${checks.length})`);
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`Treasury safety gate validation PASSED (${checks.length}/${checks.length})`);
for (const [name] of checks) console.log(`PASS ${name}`);
