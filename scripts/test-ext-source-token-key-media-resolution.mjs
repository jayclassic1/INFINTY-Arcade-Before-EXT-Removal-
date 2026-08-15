import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');

function extractFunction(name) {
  const start = html.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `${name} function exists`);
  const braceStart = html.indexOf('{', start);
  let depth = 0;
  for (let i = braceStart; i < html.length; i += 1) {
    const ch = html[i];
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return html.slice(start, i + 1);
    }
  }
  throw new Error(`Could not extract ${name}`);
}

const context = {
  console,
  isExtTokenId(tokenId) {
    if (!tokenId) return false;
    const s = String(tokenId).trim();
    return s.length > 10 && /^[a-z0-9]+-[a-z0-9]/.test(s);
  },
  getExtImageUrl(canisterId, tokenId) {
    return `https://images.entrepot.app/t/${canisterId}/${tokenId}`;
  },
  getExtImageUrlDirect(canisterId, tokenId) {
    return `https://${canisterId}.raw.icp0.io/?tokenid=${encodeURIComponent(tokenId)}`;
  },
  extTokenIdentifier(canisterId, tokenNum) {
    return `derived-${canisterId}-${tokenNum}`;
  },
};
vm.createContext(context);
vm.runInContext(`${extractFunction('getNftImageCandidates')}; this.getNftImageCandidates = getNftImageCandidates;`, context);

const canisterId = 'hhce5-bqaaa-aaaak-qtt3q-cai';
const tokenA = 'z5vci-7iaaa-aaaak-qtt3q-cai-aaaaa-aaaaq-a';
const tokenB = 'z5vci-7iaaa-aaaak-qtt3q-cai-aaaaa-aaaaq-b';

const listingA = {
  imgData: `https://${canisterId}.raw.icp0.io/?tokenid=0`,
  canisterId,
  tokenId: 0,
  sourceTokenKey: tokenA,
  collection: 'EXT: Motoko Pals',
};
const listingB = {
  imgData: `https://${canisterId}.raw.icp0.io/?tokenid=0`,
  canisterId,
  tokenId: 0,
  sourceTokenKey: tokenB,
  collection: 'EXT: Motoko Pals',
};

const candidatesA = context.getNftImageCandidates(listingA);
const candidatesB = context.getNftImageCandidates(listingB);

assert.equal(candidatesA[0], `https://images.entrepot.app/t/${canisterId}/${tokenA}`);
assert.equal(candidatesA[1], `https://images.entrepot.app/tnc/${canisterId}/${tokenA}`);
assert.equal(candidatesA[2], `https://${canisterId}.raw.icp0.io/?tokenid=${encodeURIComponent(tokenA)}`);
assert.ok(candidatesA.indexOf(listingA.imgData) > 2, 'legacy tokenId=0 imgData is only a late fallback');
assert.notDeepEqual(candidatesA.slice(0, 3), candidatesB.slice(0, 3), 'distinct sourceTokenKey values produce distinct primary media candidates');
assert.ok(!candidatesA.slice(0, 3).some((url) => url.endsWith('/0') || url.includes('tokenid=0')), 'primary EXT candidates do not collapse to numeric tokenId=0');

const numericExt = context.getNftImageCandidates({
  imgData: '',
  canisterId,
  tokenId: 42,
  sourceTokenKey: '',
  collection: 'EXT: Legacy Numeric',
});
assert.equal(numericExt[0], `https://images.entrepot.app/t/${canisterId}/derived-${canisterId}-42`);

console.log('ext_source_token_key_media_resolution=passed');
