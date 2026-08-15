import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const index = readFileSync('index.html', 'utf8');
const manifesto = readFileSync('manifesto.txt', 'utf8');
const backend = readFileSync('backend/main.mo', 'utf8');

const publicText = `${index}\n${manifesto}`;

const forbiddenPublicClaims = [
  /automated weekly earnings/i,
  /paid out automatically every week/i,
  /paid out automatically weekly/i,
  /paid out in weekly batches/i,
  /tickets?[^.\n]{0,80}(?:cash(?:ed)? out|cash-out|redeem(?:ed)? for ICP)/i,
  /redeem(?:ed)? tickets? for ICP/i,
  /tickets redeemed for it automatically becomes ICP sent to your account/i,
  /creator revenue paid as withdrawable arcade Tokens/i,
  /(?:creator|developer|seller|artist|game developer|game dev|revenue|earnings)[^.\n]{0,120}\bpaid\b[^.\n]{0,120}\bTokens\b[^.\n]{0,120}\bwithdraw\b[^.\n]{0,80}\bICP\b/i,
  /\brevenue\b[^.\n]{0,80}\bpaid\b[^.\n]{0,80}\bTokens\b[^.\n]{0,80}\bwithdraw\b[^.\n]{0,80}\bICP\b/i,
  /\bTokens\b[^.\n]{0,80}\bto your on-chain balance\b[^.\n]{0,80}\bwithdraw\b[^.\n]{0,80}\bICP\b/i,
  /TOKENS EARNED/i,
  /Dev Earnings \(Tokens\)/i,
  /\$\{devEarned\}\s*Tokens/i,
  /\bdevEarned\b[^\n]{0,80}\bTokens\b/i,
  /\b(?:creator|developer|dev|seller|artist|game developer|game dev)\b[^.\n]{0,120}\bearnings\b[^.\n]{0,120}\bTokens\b/i,
  /\b(?:creator|developer|dev|seller|artist|game developer|game dev)\b[^.\n]{0,120}\brevenue\b[^.\n]{0,120}\bTokens\b/i,
  /\bDev Earnings\b[^\n]{0,80}\bTokens\b/i,
];

for (const pattern of forbiddenPublicClaims) {
  assert.doesNotMatch(publicText, pattern, `misleading public claim remains: ${pattern}`);
}

assert.match(
  publicText,
  /Creator\s*\/\s*seller earnings accrue (?:as|in) (?:an? )?ICP-denominated claimable (?:earnings|balance)/i,
  'canonical claimable creator/seller earnings language must be present without obsolete exact copy coupling',
);
assert.match(
  publicText,
  /Tokens are arcade credits/i,
  'closed-loop token language must say Tokens are arcade credits',
);
assert.match(
  publicText,
  /Tickets are prize\/perk points/i,
  'closed-loop ticket language must say Tickets are prize/perk points',
);
assert.match(
  publicText,
  /Tickets cannot be exchanged for ICP/i,
  'closed-loop ticket language must forbid ICP cash-out',
);

assert.match(backend, /public query func getRoyalties\(/, 'backend should expose getRoyalties');
assert.match(backend, /public shared\(msg\) func claimRoyalties\(/, 'backend should expose claimRoyalties');
assert.doesNotMatch(backend, /func getAllRoyalties\(/, 'backend should not be assumed to expose getAllRoyalties');
assert.doesNotMatch(index, /getAllRoyalties\s*:/, 'frontend IDL must not advertise unsupported getAllRoyalties');
assert.doesNotMatch(index, /getTreasuryLaneBalances\s*:/, 'frontend IDL must not advertise unsupported getTreasuryLaneBalances');
assert.doesNotMatch(index, /await\s+be\.getAllRoyalties\(/, 'frontend must not call unsupported getAllRoyalties');
assert.doesNotMatch(index, /claimRoyalties removed|automated weekly batch payout/i, 'frontend IDL comments must not claim manual claim was removed for weekly payout');

console.log('creator earnings phase1 copy/IDL checks passed');
