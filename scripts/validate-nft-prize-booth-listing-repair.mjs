import fs from 'node:fs';
import assert from 'node:assert/strict';

const frontend = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const backend = fs.readFileSync(new URL('../backend/main.mo', import.meta.url), 'utf8');

function has(source, regex) {
  return regex.test(source);
}

assert.ok(has(backend, /type\s+NftListing\s*=\s*\{[\s\S]*sourceTokenKey\s*:\s*Text[\s\S]*\}/), 'NftListing must include sourceTokenKey : Text');
assert.ok(has(backend, /func\s+createExistingNftListing[\s\S]*sourceTokenKey\s*:\s*Text[\s\S]*let\s+normalizedSourceTokenKey\s*=\s*if\s*\(Text\.size\(sourceTokenKey\)\s*>\s*0\)\s*sourceTokenKey\s*else\s*Nat\.toText\(sourceTokenId\)/), 'shared listing helper must normalize sourceTokenKey with Nat fallback');
assert.ok(has(backend, /public\s+shared\(msg\)\s+func\s+listExistingNftWithTokenKey[\s\S]*sourceTokenKey\s*:\s*Text[\s\S]*createExistingNftListing\(msg\.caller[\s\S]*sourceTokenKey/), 'backend must expose additive listExistingNftWithTokenKey to preserve text token ids without changing the legacy method');
assert.ok(has(backend, /public\s+shared\(msg\)\s+func\s+listExistingNft\([\s\S]*Nat\.toText\(sourceTokenId\)/), 'legacy listExistingNft must remain and fall back sourceTokenKey to Nat.toText(sourceTokenId)');
assert.ok(has(backend, /sourceTokenKey\s*=\s*normalizedSourceTokenKey/), 'existing listing record construction must store normalizedSourceTokenKey');
assert.ok(has(backend, /registerHeldExtNftImpl[\s\S]*sourceTokenKey\s*=\s*extTokenId/), 'held EXT registration must store the full EXT token identifier as sourceTokenKey');
assert.ok(has(backend, /confirmExtEscrow[\s\S]*let\s+updatedListing\s*:\s*NftListing[\s\S]*sourceTokenKey\s*=\s*extTokenId[\s\S]*nftListings\.put\(listingId,\s*updatedListing\)/), 'confirmExtEscrow must copy confirmed EXT token id onto sourceTokenKey');
assert.ok(has(backend, /sourceTokenId\s*=\s*0;\s*sourceTokenKey\s*=\s*""/), 'minted listing path must preserve Nat compatibility and use empty sourceTokenKey');

assert.ok(has(frontend, /const\s+NftListing\s*=\s*IDL\.Record\(\{[\s\S]*sourceTokenKey\s*:\s*IDL\.Text[\s\S]*\}\)/), 'frontend IDL NftListing must expose sourceTokenKey');
assert.ok(has(frontend, /listExistingNftWithTokenKey\s*:\s*IDL\.Func\(\[IDL\.Text,IDL\.Text,IDL\.Text,IDL\.Nat,IDL\.Text,IDL\.Text,IDL\.Nat,IDL\.Text,IDL\.Text,IDL\.Nat\]/), 'frontend IDL must expose additive listExistingNftWithTokenKey with sourceTokenKey Text');
assert.ok(has(frontend, /const\s+sourceTokenKey\s*=\s*nftStandard==='ext'\?tokenId:String\(numericTokenId\)/), 'frontend EXT listing must set sourceTokenKey to the full text token id');
assert.ok(has(frontend, /be\.listExistingNftWithTokenKey\(name,''\s*,rarity,BigInt\(price\),imageUrl,canisterId,BigInt\(numericTokenId\),sourceTokenKey,collectionLabel,0n\)/), 'frontend listing creation must pass sourceTokenKey before collectionName/feeTxId');
assert.ok(!has(frontend, /For backend sourceTokenId: EXT uses text IDs, store 0 and keep full ID in image URL/), 'frontend must not document image URL as the only full EXT token identity storage');
assert.ok(has(frontend, /const\s+sourceTokenKey=String\(l\.sourceTokenKey\|\|l\.sourceTokenId\|\|''\)/), 'frontend listing mapping must prefer sourceTokenKey with numeric fallback');
assert.ok(has(frontend, /tokenIdForEscrow=listing\.sourceTokenKey\|\|''/), 'EXT escrow confirmation must prefer listing.sourceTokenKey instead of reconstructing from image URL');
assert.ok(has(frontend, /String\(s\.sourceTokenKey\|\|''\)===tokenId/), 'custody listing matcher must match by sourceTokenKey');

console.log('validate-nft-prize-booth-listing-repair: ok');
