#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const sourcePath = path.join(root, 'backend', 'main.mo');
const source = fs.readFileSync(sourcePath, 'utf8').replace(/\r\n/g, '\n');

const failures = [];
const passes = [];

function test(name, predicate, detail) {
  try {
    if (predicate()) {
      passes.push(name);
    } else {
      failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
    }
  } catch (error) {
    failures.push(`${name} — threw ${error.message}`);
  }
}

function indexOfRequired(haystack, needle, label = needle) {
  const index = haystack.indexOf(needle);
  if (index === -1) failures.push(`missing required marker: ${label}`);
  return index;
}

const claimMatch = /public\s+shared\s*\(msg\)\s+func\s+claimRoyalties\s*\(\)\s*:\s*async\s+Result\.Result<Nat,\s*Text>/.exec(source);
const claimStart = claimMatch ? claimMatch.index : -1;
const claimEnd = claimStart === -1 ? -1 : source.indexOf('// ============================================\n  // === NFT ESCROW', claimStart);
const claimBody = claimStart === -1 || claimEnd === -1 ? '' : source.slice(claimStart, claimEnd);

test('claimRoyalties exists', () => claimStart !== -1 && claimEnd !== -1);
test('claim rejects anonymous callers', () => /Principal\.isAnonymous\(caller\)[\s\S]{0,80}#err\("Must be authenticated"\)/.test(claimBody));
test('claim rejects zero balance with a clear error', () => /balance\s*==\s*0[\s\S]{0,160}(?:No royalties to claim|No claimable creator\/seller earnings or refunds)/.test(claimBody));
test('claim rejects dust below explicit e8s minimum', () => /ROYALTY_CLAIM_MIN_E8S/.test(source) && /balance\s*<\s*ROYALTY_CLAIM_MIN_E8S[\s\S]{0,180}Minimum royalty claim/.test(claimBody));
test('claim locks/debits all claimable buckets before any ledger await', () => {
  const gameCreatorDebit = claimBody.indexOf('royalties.put(caller, 0)');
  const nftSellerDebit = claimBody.indexOf('nftSellerEarningsE8s.put(caller, 0)');
  const refundDebit = claimBody.indexOf('refundsE8s.put(caller, 0)');
  const ledgerAwait = claimBody.search(/await\s+ICP_LEDGER/);
  return gameCreatorDebit !== -1 && nftSellerDebit !== -1 && refundDebit !== -1 && ledgerAwait !== -1
    && gameCreatorDebit < ledgerAwait && nftSellerDebit < ledgerAwait && refundDebit < ledgerAwait;
}, 'expected royalties, nftSellerEarningsE8s, and refundsE8s debited before await ICP_LEDGER*');
test('claim restores debited game creator, NFT seller, and refund balances on ledger #Err result', () => {
  const errStart = claimBody.indexOf('case (#Err(e))');
  if (errStart === -1) return false;
  const errEnd = claimBody.indexOf('switch (e)', errStart);
  if (errEnd === -1) return false;
  const errPrelude = claimBody.slice(errStart, errEnd);
  return /restoreGameCreatorEarningsBalance\(caller, gameCreatorEarningsBalance\)/.test(errPrelude)
    && /restoreNftSellerEarningsBalance\(caller, nftSellerEarningsBalance\)/.test(errPrelude)
    && /restoreRefundBalance\(caller, refundBalance\)/.test(errPrelude);
});
test('claim restores debited game creator, NFT seller, and refund balances on transfer trap', () => {
  const catchStart = claimBody.indexOf('catch (e)');
  if (catchStart === -1) return false;
  const catchBody = claimBody.slice(catchStart, claimBody.indexOf('#err("Royalty claim transfer error', catchStart));
  return /restoreGameCreatorEarningsBalance\(caller, gameCreatorEarningsBalance\)/.test(catchBody)
    && /restoreNftSellerEarningsBalance\(caller, nftSellerEarningsBalance\)/.test(catchBody)
    && /restoreRefundBalance\(caller, refundBalance\)/.test(catchBody);
});
test('restore helpers preserve credits accrued while claim awaited', () => {
  const gameCreatorRestore = /func restoreGameCreatorEarningsBalance\(creator : Principal, amountE8s : Nat\)[\s\S]{0,220}getGameCreatorEarningsBalance\(creator\)[\s\S]{0,160}current \+ amountE8s/.test(source);
  const nftSellerRestore = /func restoreNftSellerEarningsBalance\(seller : Principal, amountE8s : Nat\)[\s\S]{0,220}getNftSellerEarningsBalance\(seller\)[\s\S]{0,160}current \+ amountE8s/.test(source);
  const refundRestore = /func restoreRefundBalance\(creator : Principal, amountE8s : Nat\)[\s\S]{0,220}getRefundBalance\(creator\)[\s\S]{0,160}current \+ amountE8s/.test(source);
  return gameCreatorRestore && nftSellerRestore && refundRestore;
});
test('successful claim leaves caller royalty balance locked at zero', () => {
  const okStart = claimBody.indexOf('case (#Ok(_blockIndex))');
  if (okStart === -1) return false;
  const okEnd = claimBody.indexOf('};', okStart);
  if (okEnd === -1) return false;
  const okCase = claimBody.slice(okStart, okEnd);
  return /#ok\(balance\)/.test(okCase) && !/restoreRoyaltyBalance/.test(okCase);
});
test('claim uses ICP e8s royalties only, not tickets', () => !/ticket|tickets|Ticket/.test(claimBody));
test('creditRoyalty documents ICP e8s denomination', () => /creditRoyalty\(creator : Principal, amountE8s : Nat\)/.test(source));

if (failures.length > 0) {
  console.error('Creator earnings Phase 2 validation FAILED');
  for (const failure of failures) console.error(`❌ ${failure}`);
  if (passes.length > 0) {
    console.error('\nPassed checks:');
    for (const pass of passes) console.error(`✅ ${pass}`);
  }
  process.exit(1);
}

console.log(`Creator earnings Phase 2 validation PASSED (${passes.length}/${passes.length})`);
for (const pass of passes) console.log(`✅ ${pass}`);
