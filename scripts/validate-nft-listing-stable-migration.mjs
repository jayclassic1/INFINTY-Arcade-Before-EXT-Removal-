import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const backend = readFileSync(new URL('../backend/main.mo', import.meta.url), 'utf8');

const has = (re) => re.test(backend);

assert.ok(
  has(/type\s+NftListingStable\s*=\s*\{[\s\S]*sourceTokenId\s*:\s*Nat[\s\S]*collectionName\s*:\s*Text[\s\S]*\}/),
  'backend must define an old-compatible NftListingStable record for stable nftListingEntries'
);

const stableType = backend.match(/stable\s+var\s+nftListingEntries\s*:\s*([^=]+)=/);
assert.ok(stableType, 'backend must declare stable nftListingEntries');
assert.equal(
  stableType[1].replace(/\s+/g, ' ').trim(),
  '[(Text, NftListingStable)]',
  'stable nftListingEntries must remain old-compatible; storing [(Text, NftListing)] would require sourceTokenKey and break upgrade decoding'
);

assert.ok(
  has(/stable\s+var\s+nftListingSourceTokenKeyEntries\s*:\s*\[\(Text,\s*Text\)\]\s*=\s*\[\]/),
  'backend must store sourceTokenKey in a separate additive stable array'
);

assert.ok(
  has(/func\s+nftListingToStable\s*\(listing\s*:\s*NftListing\)\s*:\s*NftListingStable/),
  'backend must convert runtime NftListing to old-compatible stable storage in preupgrade'
);

assert.ok(
  has(/func\s+hydrateNftListing\s*\([^)]*stableListing\s*:\s*NftListingStable[\s\S]*\)\s*:\s*NftListing[\s\S]*sourceTokenKey\s*=\s*nftListingSourceTokenKeyFallback/),
  'backend must hydrate stable listings into runtime NftListing with deterministic sourceTokenKey fallback'
);

assert.ok(
  has(/nftListingEntries\s*:=\s*Array\.map<\(Text,\s*NftListing\),\s*\(Text,\s*NftListingStable\)>/),
  'preupgrade must persist nftListings through nftListingToStable instead of writing runtime NftListing directly'
);

assert.ok(
  has(/nftListingSourceTokenKeyEntries\s*:=\s*Array\.map<\(Text,\s*NftListing\),\s*\(Text,\s*Text\)>/),
  'preupgrade must persist sourceTokenKey separately as an additive stable array'
);

assert.ok(
  has(/for\s*\(\(listingId,\s*stableListing\)\s+in\s+nftListingEntries\.vals\(\)\)\s*\{[\s\S]*nftListings\.put\(listingId,\s*hydrateNftListing\(listingId,\s*stableListing\)\)/),
  'runtime hydration must migrate each stable listing with hydrateNftListing before inserting into nftListings'
);

assert.ok(
  !has(/nftListings\s*:=\s*HashMap\.fromIter<Text,\s*NftListing>\(nftListingEntries\.vals\(\)/),
  'runtime hydration must not directly decode stable nftListingEntries as runtime NftListing'
);

console.log('ok');
