import fs from 'node:fs';
import assert from 'node:assert/strict';

const frontend = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const backend = fs.readFileSync(new URL('../backend/main.mo', import.meta.url), 'utf8');

function has(source, regex) {
  return regex.test(source);
}

assert.ok(has(backend, /transient let NFT_LISTING_FEE_TOKENS\s*:\s*Nat\s*=\s*2;/), 'backend listing fee constant must be 2 Tokens');
assert.ok(has(backend, /transient let NFT_LISTING_FEE_E8S\s*:\s*Nat\s*=\s*NFT_LISTING_FEE_TOKENS \* TOKEN_LIABILITY_E8S;/), 'backend ICP-equivalent listing fee must derive from token liability rate');
assert.ok(has(backend, /func chargeNftListingFee\(caller : Principal\) : Result\.Result<\(\), Text>/), 'backend must have a listing fee charging helper');
assert.ok(has(backend, /if \(isAdmin\(caller\)\) return #ok\(\(\)\);/), 'backend listing fee helper must keep admin exemption explicit');
assert.ok(has(backend, /tokens\.put\(caller, balance - NFT_LISTING_FEE_TOKENS\);/), 'backend must deduct the listing fee from user tokens');
assert.ok(has(backend, /switch \(chargeNftListingFee\(caller\)\)/), 'listExistingNft must enforce fee server-side');
assert.ok(has(backend, /feePaid = NFT_LISTING_FEE_E8S; \/\/ 2 Tokens = 0\.02 ICP equivalent/), 'listing record feePaid should use the 2-token ICP equivalent');
assert.ok(has(backend, /logRevenue\("nft-list", NFT_LISTING_FEE_E8S, caller, 1\);/), 'nft-list revenue log should use the new listing fee');

assert.ok(frontend.includes('Verify & List · 2 Tokens'), 'listing button must display 2 Tokens');
assert.ok(frontend.includes('You need 2 Tokens'), 'pre-transfer token pre-check must require 2 Tokens');
assert.ok(frontend.includes('Listing an NFT costs 2 Tokens'), 'listing failure copy must say 2 Tokens');
assert.ok(frontend.includes('Listing Fee: 2 Tokens'), 'confirmation title must say 2 Tokens');
assert.ok(frontend.includes('2 Tokens will be deducted from your balance.'), 'confirmation body must say 2 Tokens will be deducted');
assert.ok(!frontend.includes('Verify & List · 10 Tokens'), 'old 10-token listing button copy must be gone');
assert.ok(!frontend.includes('You need 10 Tokens'), 'old 10-token pre-check copy must be gone');
assert.ok(!frontend.includes('Listing an NFT costs 10 Tokens'), 'old 10-token listing error copy must be gone');
assert.ok(!frontend.includes('Listing Fee: 10 Tokens'), 'old 10-token confirmation title must be gone');

console.log('validate-nft-listing-fee: ok');
