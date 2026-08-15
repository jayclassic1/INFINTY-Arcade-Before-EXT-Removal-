#!/usr/bin/env node
import fs from 'node:fs';
import assert from 'node:assert/strict';

const backend = fs.readFileSync('backend/main.mo', 'utf8');
const frontend = fs.readFileSync('index.html', 'utf8');
const has = (text, re) => re.test(text);
const indexOfRequired = (text, needle, message) => {
  const idx = text.indexOf(needle);
  assert.notEqual(idx, -1, message);
  return idx;
};

// Backend: additive pending flow exists and preserves the full EXT token key while non-live.
assert.ok(has(backend, /func\s+createPendingExistingNftListing[\s\S]*status\s*=\s*"pending_escrow"[\s\S]*sourceTokenKey\s*=\s*normalizedSourceTokenKey/), 'backend must create pending_escrow NFT listings with the normalized full sourceTokenKey');
assert.ok(has(backend, /public\s+shared\(msg\)\s+func\s+createPendingExistingNftListingWithTokenKey[\s\S]*sourceTokenKey\s*:\s*Text[\s\S]*createPendingExistingNftListing\(msg\.caller[\s\S]*sourceTokenKey/), 'backend must expose createPendingExistingNftListingWithTokenKey for EXT-safe pending listings');
assert.ok(has(backend, /confirmExtEscrow[\s\S]*not\s+Text\.equal\(listing\.sourceTokenKey,\s*extTokenId\)[\s\S]*#err\("Escrow token mismatch/), 'confirmExtEscrow must reject confirmation unless the full extTokenId matches listing.sourceTokenKey');
assert.ok(has(backend, /confirmExtEscrow[\s\S]*status\s*=\s*if\s*\(listing\.status\s*==\s*"pending_escrow"\)\s*"live"\s*else\s*listing\.status/), 'confirmExtEscrow must activate pending_escrow listings to live only after custody verification');
assert.ok(has(backend, /removeNftListing[\s\S]*listing\.status\s*==\s*"pending_escrow"[\s\S]*Principal\.equal\(listing\.creator,\s*msg\.caller\)/), 'pending NFT listings must be cancellable by their creator while preserving admin safety checks');
assert.ok(has(backend, /getNftListings\(\)[\s\S]*Array\.filter<NftListing>\(all,\s*func\(l\)\s*\{\s*l\.status\s*==\s*"live"\s*\}\)/), 'getNftListings must filter pending_escrow listings out of purchasable/live results');

// Frontend IDL: pending creation method is available to the safer EXT flow.
assert.ok(has(frontend, /createPendingExistingNftListingWithTokenKey\s*:\s*IDL\.Func\(\[IDL\.Text,IDL\.Text,IDL\.Text,IDL\.Nat,IDL\.Text,IDL\.Text,IDL\.Nat,IDL\.Text,IDL\.Text,IDL\.Nat\]/), 'frontend IDL must expose createPendingExistingNftListingWithTokenKey');

const flowStart = indexOfRequired(frontend, 'async function verifyAndListNft()', 'verifyAndListNft flow must exist');
const flowEnd = indexOfRequired(frontend.slice(flowStart), '// === AUTO-RARITY', 'verifyAndListNft flow end marker must exist') + flowStart;
const flow = frontend.slice(flowStart, flowEnd);

const pendingIdx = indexOfRequired(flow, 'createPendingExistingNftListingWithTokenKey', 'verifyAndListNft EXT path must create pending listing before transfer');
const transferIdx = indexOfRequired(flow, 'extActorAuth.transfer', 'verifyAndListNft EXT path must still transfer to escrow after pending creation');
assert.ok(pendingIdx < transferIdx, 'EXT transfer must not appear before pending listing creation in verifyAndListNft');
assert.ok(has(flow, /confirmExtEscrow\(pending\.listingId,\s*canId,\s*tokenId\)/), 'verifyAndListNft must confirm escrow using the pending listing id and full EXT token id');
assert.ok(has(frontend, /function\s+renderPendingExtRecovery[\s\S]*Pending listing ID:[\s\S]*pending\.listingId[\s\S]*Canister ID:[\s\S]*canId[\s\S]*Full token ID:[\s\S]*tokenId[\s\S]*Status:[\s\S]*pending_escrow/), 'if confirm fails after transfer, UI must show recoverable pending listing id, canister id, full token id, and status');
assert.ok(has(flow, /renderPendingExtRecovery\(resEl,pending,canId,tokenId,confirmErr\)/), 'verifyAndListNft must route failed post-transfer confirmation to pending recovery UI');
assert.ok(has(frontend, /function\s+animateNftVerifyListButton[\s\S]*nftVerifyListBtn[\s\S]*arcade-hit/) && has(flow, /animateNftVerifyListButton\('Verifying\.\.\.'\)/), 'Verify & List button should use a clear click animation/status state');
assert.ok(!has(flow, /Admin recovery needed: the NFT was transferred before a listing\/escrow record was created/), 'new EXT flow must not report no record exists after transfer because pending record is created first');

console.log('✅ pending escrow NFT listing validator passed');
