#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const backend = readFileSync('backend/main.mo', 'utf8');
const frontend = readFileSync('index.html', 'utf8');
const deployFrontend = readFileSync('.deploy/frontend-public/index.html', 'utf8');

function extractFunction(source, name) {
  const start = source.search(new RegExp(`(?:public\\s+shared(?:\\([^)]*\\))?|func)\\s+${name}\\s*\\(`));
  assert.notEqual(start, -1, `${name} must exist`);
  const brace = source.indexOf('{', start);
  assert.notEqual(brace, -1, `${name} must have a body`);
  let depth = 0;
  for (let i = brace; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  throw new Error(`Could not extract ${name}`);
}

const impl = extractFunction(backend, 'adminWithdrawOperatingTreasuryImpl');
const method = extractFunction(backend, 'adminWithdrawOperatingTreasury');
const principalWrapper = extractFunction(backend, 'adminWithdrawTreasury');
const getTreasuryBalance = extractFunction(backend, 'getTreasuryBalance');

assert.match(method, /if \(not isAdmin\(msg\.caller\)\) return #err\("Admin only"\)/, 'operating withdrawal must be admin-only');
assert.match(method, /await adminWithdrawOperatingTreasuryImpl\(destination, amountE8s\)/, 'public operating method must delegate to shared implementation');
assert.match(principalWrapper, /if \(not isAdmin\(msg\.caller\)\) return #err\("Admin only"\)/, 'legacy principal wrapper must remain admin-only');
assert.match(principalWrapper, /subaccount = null/, 'principal wrapper must send to the destination principal main account only');

assert.match(backend, /transient let ICP_LEDGER_FEE_E8S\s*:\s*Nat\s*=\s*10_000/, 'ledger fee constant must be explicit');
assert.match(backend, /transient var operatingTreasuryWithdrawalInFlight\s*=\s*false/, 'operating withdrawal must have a reentrancy guard');
assert.match(impl, /if \(operatingTreasuryWithdrawalInFlight\) return #err\("Operating Treasury withdrawal already in progress"\)/, 'must reject overlapping operating withdrawals');
assert.match(impl, /if \(amountE8s <= ICP_LEDGER_FEE_E8S\)/, 'must reject zero and dust amounts that cannot cover fee');
assert.match(impl, /operatingTreasuryWithdrawalInFlight := true/, 'must set lock before ledger awaits');
assert.match(impl, /operatingTreasuryWithdrawalInFlight := false/g, 'must clear lock on every error/success path');

assert.match(impl, /icrc1_balance_of\(\{ owner = selfPrincipal; subaccount = \?OPERATING_TREASURY_SUBACCOUNT \}\)/, 'must read operating treasury balance only');
assert.match(impl, /let requiredE8s = amountE8s \+ ICP_LEDGER_FEE_E8S/, 'must define amount as net transfer amount plus fee requirement');
assert.match(impl, /if \(operatingBalanceE8s < requiredE8s\)/, 'must guard amount plus fee against operating balance');
assert.match(impl, /from_subaccount = \?OPERATING_TREASURY_SUBACCOUNT/, 'transfer must draw from operating subaccount only');
assert.doesNotMatch(impl, /from_subaccount = null/, 'operating withdrawal must never draw from protected/main treasury');
assert.doesNotMatch(impl, /getTreasuryBalance\(\)|reservedE8s|withdrawableE8s|protectedE8s/, 'operating withdrawal must not consult or reduce protected/backing reserve math');
assert.match(backend, /func icpTransferErrorText[\s\S]*#TooOld[\s\S]*#CreatedInFuture[\s\S]*#Duplicate[\s\S]*#TemporarilyUnavailable[\s\S]*#GenericError[\s\S]*#BadBurn/, 'must return clear ledger errors');

assert.match(getTreasuryBalance, /subaccount = null/, 'getTreasuryBalance must remain protected/main account only');
assert.doesNotMatch(getTreasuryBalance, /OPERATING_TREASURY_SUBACCOUNT|operatingBalanceE8s|adminWithdrawOperatingTreasury/, 'getTreasuryBalance must not include operating treasury state or withdrawals');

for (const [name, source] of [['index.html', frontend], ['.deploy/frontend-public/index.html', deployFrontend]]) {
  assert.match(source, /adminWithdrawOperatingTreasury:IDL\.Func\(\[IDL\.Record\(\{owner:IDL\.Principal,subaccount:IDL\.Opt\(IDL\.Vec\(IDL\.Nat8\)\)\}\),IDL\.Nat\],\[ResultNat\],\[\]\)/, `${name}: IDL must expose adminWithdrawOperatingTreasury Account method`);
  assert.match(source, /Operating Treasury withdrawal/i, `${name}: admin copy must explicitly name Operating Treasury withdrawal`);
  assert.match(source, /separate from Protected \/ Backing/i, `${name}: admin copy must state operating withdrawal is separate from protected/backing controls`);
  assert.match(source, /backendMethodAvailable\(be,'adminWithdrawOperatingTreasury'\)/, `${name}: frontend must gate the new method by backend availability`);
  assert.match(source, /be\.adminWithdrawOperatingTreasury\(\{owner:destPrincipal,subaccount:\[\]\},amountE8s\)/, `${name}: frontend principal withdrawal must call operating Account method`);
}

console.log('treasury operating withdraw phase3 validation passed');
