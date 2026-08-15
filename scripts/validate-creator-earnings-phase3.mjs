#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const backendPath = path.join(root, 'backend', 'main.mo');
const frontendPath = path.join(root, 'index.html');
const backend = fs.readFileSync(backendPath, 'utf8');
const frontend = fs.readFileSync(frontendPath, 'utf8');

const failures = [];
const passes = [];

function test(name, predicate, detail) {
  try {
    if (predicate()) passes.push(name);
    else failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
  } catch (error) {
    failures.push(`${name} — threw ${error.message}`);
  }
}

function sliceBetween(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  if (start === -1) return '';
  const end = endMarker ? source.indexOf(endMarker, start) : -1;
  return source.slice(start, end === -1 ? undefined : end);
}

const royaltyPutMatches = [...backend.matchAll(/royalties\.put\(([^\n]+)\)/g)].map(m => ({ text: m[0], index: m.index ?? -1 }));
const allowedRoyaltyContexts = [
  'restoreRoyaltyBalance',
  'restoreGameCreatorEarningsBalance',
  'spendTokensOnGame',
  'creditRoyalty',
  'claimRoyalties'
];

function enclosingFunctionName(index) {
  const prefix = backend.slice(0, index);
  const match = [...prefix.matchAll(/(?:public\s+(?:shared\(msg\)\s+)?func|func)\s+([A-Za-z0-9_]+)\s*\(/g)].pop();
  return match?.[1] || 'unknown';
}

test('all royalty map writes are limited to ICP-e8s earning/claim helpers', () => {
  const unexpected = royaltyPutMatches
    .map(hit => ({ ...hit, fn: enclosingFunctionName(hit.index) }))
    .filter(hit => !allowedRoyaltyContexts.includes(hit.fn));
  return unexpected.length === 0;
}, `unexpected royalty writes: ${royaltyPutMatches.map(hit => ({ ...hit, fn: enclosingFunctionName(hit.index) })).filter(hit => !allowedRoyaltyContexts.includes(hit.fn)).map(hit => `${hit.fn}:${hit.text}`).join('; ')}`);

test('reject/application/removal refunds use a separate refund balance, not royalties', () => {
  const refundFns = ['rejectNftShowroom', 'rejectGameShowroom', 'removeGameSubmission'];
  return refundFns.every(fn => {
    const body = sliceBetween(backend, `func ${fn}`, '\n  //');
    return body && /creditRefundE8s\(/.test(body) && !/royalties\.put/.test(body);
  });
}, 'refund flows must call creditRefundE8s and must not write royalties');

test('claim path includes game creator earnings, NFT seller earnings, and separate refund balance atomically', () => {
  const body = sliceBetween(backend, 'public shared(msg) func claimRoyalties()', '// ============================================\n  // === NFT ESCROW');
  return /gameCreatorEarningsBalance\s*=\s*getGameCreatorEarningsBalance\(caller\)/.test(body)
    && /nftSellerEarningsBalance\s*=\s*getNftSellerEarningsBalance\(caller\)/.test(body)
    && /refundBalance\s*=\s*getRefundBalance\(caller\)/.test(body)
    && /let balance\s*=\s*gameCreatorEarningsBalance \+ nftSellerEarningsBalance \+ refundBalance/.test(body)
    && /royalties\.put\(caller, 0\)/.test(body)
    && /nftSellerEarningsE8s\.put\(caller, 0\)/.test(body)
    && /refundsE8s\.put\(caller, 0\)/.test(body);
});

test('ticket-based user NFT redemption credits only separate NFT seller earnings after transfer success', () => {
  const body = sliceBetween(backend, 'func redeemUserNft', '\n  /// Return escrowed');
  if (!body) return false;
  const successStart = body.indexOf('case (#ok(_))');
  if (successStart === -1) return false;
  const successBody = body.slice(successStart);
  return !/royalties\.put/.test(body)
    && !/creatorShare/.test(body)
    && /let sellerPayoutE8s\s*=\s*ticketCostToSellerPayoutE8s\(cost\)/.test(successBody)
    && /tickets\.put\(caller, balance - cost\)/.test(successBody)
    && /creditNftSellerEarnings\(listing\.creator, sellerPayoutE8s\)/.test(successBody)
    && /logRevenue\("nft-redeem", sellerPayoutE8s/.test(successBody);
}, 'redeemUserNft must not write game creator royalties and must credit the separate NFT seller bucket after NFT transfer success');

test('backend comments state legacy royalties are game creator ICP e8s and refunds are separate', () => {
  return /game creator royalty balance query \(ICP owed, in e8s\)/i.test(backend)
    && /Refund[^\n]*separate (?:ICP )?refund balance|separate refund balance/i.test(backend);
});

test('frontend refund wording does not call refunds creator earnings', () => {
  return !/refund credited to creator earnings balance/i.test(frontend)
    && /refund credited to your separate ICP refund balance/i.test(frontend);
});

test('closed-loop Tokens and Tickets product copy remains present', () => {
  return /Tokens are arcade credits/i.test(frontend)
    && /Tickets are prize\/perk points/i.test(frontend)
    && /Tickets cannot be exchanged for ICP/i.test(frontend);
});

test('no stale seller ticket-to-game-royalty or deferred-payout wording remains', () => {
  const forbidden = [
    /ticket-based seller ICP payout deferred/i,
    /ticket value to NFT creator/i,
    /tickets?.{0,80}credit.{0,80}royalt/i,
    /redeemUserNft[\s\S]{0,2200}royalties\.put/i
  ];
  return forbidden.every(pattern => !pattern.test(backend) && !pattern.test(frontend));
});

if (failures.length > 0) {
  console.error('Creator earnings Phase 3 validation FAILED');
  for (const failure of failures) console.error(`❌ ${failure}`);
  if (passes.length > 0) {
    console.error('\nPassed checks:');
    for (const pass of passes) console.error(`✅ ${pass}`);
  }
  process.exit(1);
}

console.log(`Creator earnings Phase 3 validation PASSED (${passes.length}/${passes.length})`);
for (const pass of passes) console.log(`✅ ${pass}`);
