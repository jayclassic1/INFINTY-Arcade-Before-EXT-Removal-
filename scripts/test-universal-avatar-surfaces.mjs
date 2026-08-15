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

function buildContext({ currentPrincipal = 'own-principal', profile = null, publicProfiles = {} } = {}) {
  const localStore = new Map([
    ['arcade_public_profiles', JSON.stringify(publicProfiles)],
  ]);
  if (profile) localStore.set(`arcade_profile_${currentPrincipal}`, JSON.stringify(profile));

  const context = {
    console,
    window: {},
    S: { principalText: currentPrincipal },
    localStore,
    document: { createElement() { return { textContent: '', innerHTML: '' }; } },
    localStorage: {
      getItem(key) { return localStore.has(key) ? localStore.get(key) : null; },
      setItem(key, value) { localStore.set(key, String(value)); },
    },
    isExtTokenId(tokenId) {
      if (!tokenId) return false;
      const s = String(tokenId).trim();
      return s.length > 10 && /^[a-z0-9]+-[a-z0-9]/.test(s);
    },
    getExtImageUrl(canisterId, tokenId) { return `https://images.entrepot.app/t/${canisterId}/${tokenId}`; },
    getExtImageUrlDirect(canisterId, tokenId) { return `https://${canisterId}.raw.icp0.io/?tokenid=${encodeURIComponent(tokenId)}`; },
    extTokenIdentifier(canisterId, tokenNum) { return `derived-${canisterId}-${tokenNum}`; },
  };
  vm.createContext(context);
  vm.runInContext(`
${extractFunction('buildNftImageTag')}
${extractFunction('getNftImageCandidates')}
${extractFunction('normalizeProfileAvatarNft')}
${extractFunction('getProfileAvatarCandidates')}
${extractFunction('buildProfileAvatarImageTag')}
${extractFunction('getPublicProfiles')}
${extractFunction('savePublicProfile')}
${extractFunction('getAvatarProfileSnapshot')}
${extractFunction('getProfileFor')}
${extractFunction('getProfile')}
${extractFunction('registerPublicPresence')}
${extractFunction('resolveAvatar')}
${extractFunction('renderSquareAvatar')}
this.resolveAvatar = resolveAvatar;
this.renderSquareAvatar = renderSquareAvatar;
this.registerPublicPresence = registerPublicPresence;
`, context);
  return context;
}

const canisterId = 'hhce5-bqaaa-aaaak-qtt3q-cai';
const sourceTokenKey = 'z5vci-7iaaa-aaaak-qtt3q-cai-aaaaa-aaaaq-a';
const legacyBadUrl = `https://${canisterId}.raw.icp0.io/?tokenid=0`;
const avatarNft = {
  collection: 'Motoko Pals',
  canisterId,
  tokenId: sourceTokenKey,
  sourceTokenKey,
  standard: 'EXT v2',
  standardKey: 'ext',
  imageUrl: legacyBadUrl,
  name: 'Motoko Pals #0',
};

{
  const context = buildContext({ profile: { name: 'Jay', avatarUrl: legacyBadUrl, avatarNft } });
  const avatarValue = context.resolveAvatar(legacyBadUrl, 'own-principal');
  const htmlOut = context.renderSquareAvatar(avatarValue, 36, 8);
  assert.ok(htmlOut.includes('data-candidates'), 'own forum/DAO avatar renders fallback candidates from avatarNft metadata');
  assert.ok(htmlOut.includes(sourceTokenKey), 'own forum/DAO avatar candidates include EXT sourceTokenKey media URL');
  assert.ok(htmlOut.indexOf(sourceTokenKey) < htmlOut.indexOf(legacyBadUrl), 'metadata candidates are preferred ahead of stale avatarUrl');
}

{
  const context = buildContext({
    publicProfiles: {
      'other-principal': { name: 'Other', avatarUrl: legacyBadUrl, avatarNft },
    },
  });
  const avatarValue = context.resolveAvatar('https://stale.example/avatar.png', 'other-principal');
  const htmlOut = context.renderSquareAvatar(avatarValue, 28, 6);
  assert.ok(htmlOut.includes('data-candidates'), 'known other-user avatar renders public profile metadata candidates');
  assert.ok(htmlOut.includes(sourceTokenKey), 'known other-user avatar candidates include EXT sourceTokenKey media URL');
}

{
  const context = buildContext({ profile: { name: 'Jay', avatarUrl: legacyBadUrl, avatarNft, bio: 'Arcade' } });
  context.registerPublicPresence('own-principal', 'forum');
  const publicProfiles = JSON.parse(context.localStore.get('arcade_public_profiles'));
  assert.equal(publicProfiles['own-principal'].avatarUrl, legacyBadUrl, 'public profile keeps legacy avatarUrl for compatibility');
  assert.equal(publicProfiles['own-principal'].avatarNft.sourceTokenKey, sourceTokenKey, 'public profile snapshots avatarNft metadata');
}

{
  const context = buildContext({ profile: { name: 'Legacy', avatarUrl: 'https://example.com/avatar.png' } });
  const avatarValue = context.resolveAvatar('https://example.com/avatar.png', 'own-principal');
  const htmlOut = context.renderSquareAvatar(avatarValue, 40, 8);
  assert.ok(htmlOut.includes('https://example.com/avatar.png'), 'legacy avatarUrl-only profiles still render');
}

const authorAvatarNftSnapshots = (html.match(/authorAvatarNft:profile\?\.avatarNft\?normalizeProfileAvatarNft\(profile\.avatarNft\):null/g) || []).length;
assert.ok(authorAvatarNftSnapshots >= 4, 'forum and DAO posts/replies snapshot avatarNft metadata');
assert.ok(html.includes('resolveAvatar(p.authorAvatar,p.principal,p.authorAvatarNft)'), 'forum/DAO thread cards pass stored avatar metadata into resolver');
assert.ok(html.includes('resolveAvatar(r.authorAvatar,r.principal,r.authorAvatarNft)'), 'forum/DAO replies pass stored avatar metadata into resolver');

console.log('universal_avatar_surfaces=passed');
