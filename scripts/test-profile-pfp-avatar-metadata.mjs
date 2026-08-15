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

const savedProfiles = [];
const context = {
  console,
  window: {},
  selectedAvatarUrl: null,
  editAvatarUrl: null,
  editAvatarNft: null,
  profileNfts: [],
  document: { getElementById() { return null; } },
  qs(id) {
    if (id === 'editProfileName') return { value: 'Jay' };
    if (id === 'editProfileBio') return { value: 'Arcade profile' };
    return { innerHTML: '', textContent: '', value: '', style: {}, classList: { add() {}, remove() {}, toggle() {} } };
  },
  getProfile() { return savedProfiles.at(-1) || { name: 'Jay', bio: 'old', avatarUrl: '' }; },
  saveProfileData(profile) { savedProfiles.push(profile); },
  updateProfileDisplay() {},
  renderProfileView() {},
  closeProfileEdit() {},
  updateEditAvatarPreview() {},
  renderEditAvatarPicker() {},
  escHtml(s) { return String(s ?? ''); },
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
${extractFunction('getNftImageCandidates')}
${extractFunction('normalizeProfileAvatarNft')}
${extractFunction('getProfileAvatarCandidates')}
${extractFunction('buildProfileAvatarImageTag')}
${extractFunction('buildNftImageTag')}
${extractFunction('setProfilePfpFromCollectionNft')}
${extractFunction('renderNftPicker')}
${extractFunction('pickEditAvatar')}
${extractFunction('saveProfileEdit')}
this.getProfileAvatarCandidates = getProfileAvatarCandidates;
this.setProfilePfpFromCollectionNft = setProfilePfpFromCollectionNft;
this.renderNftPicker = renderNftPicker;
this.pickEditAvatar = pickEditAvatar;
this.saveProfileEdit = saveProfileEdit;
`, context);

const canisterId = 'hhce5-bqaaa-aaaak-qtt3q-cai';
const sourceTokenKey = 'z5vci-7iaaa-aaaak-qtt3q-cai-aaaaa-aaaaq-a';
const legacyBadUrl = `https://${canisterId}.raw.icp0.io/?tokenid=0`;
const nft = {
  collection: 'Motoko Pals',
  canisterId,
  index: 0,
  tokenId: sourceTokenKey,
  sourceTokenKey,
  standard: 'EXT v2',
  standardKey: 'ext',
  name: 'Motoko Pals #0',
  imageUrl: legacyBadUrl,
};

context.setProfilePfpFromCollectionNft(JSON.stringify(nft));
const saved = savedProfiles.at(-1);
assert.equal(saved.avatarUrl, legacyBadUrl, 'legacy avatarUrl remains populated for backend compatibility');
assert.equal(saved.avatarNft.sourceTokenKey, sourceTokenKey, 'selected PFP stores sourceTokenKey metadata');
assert.equal(saved.avatarNft.standardKey, 'ext', 'selected PFP stores NFT standard metadata');

const candidates = context.getProfileAvatarCandidates(saved);
assert.equal(candidates[0], `https://images.entrepot.app/t/${canisterId}/${sourceTokenKey}`);
assert.equal(candidates[1], `https://images.entrepot.app/tnc/${canisterId}/${sourceTokenKey}`);
assert.ok(candidates.indexOf(legacyBadUrl) > 2, 'legacy avatarUrl is retained only as a late fallback');

context.profileNfts = [{
  id: 0,
  name: 'Motoko Pals #0',
  image: legacyBadUrl,
  canister: canisterId,
  canisterId,
  tokenId: sourceTokenKey,
  sourceTokenKey,
  collection: 'Motoko Pals',
  standard: 'EXT v2',
  standardKey: 'ext',
}];

const pickerEl = { innerHTML: '' };
context.renderNftPicker(pickerEl, legacyBadUrl, 'pickEditAvatar');
assert.ok(pickerEl.innerHTML.includes('data-candidates'), 'edit picker renders NFT image fallback candidates');
assert.ok(pickerEl.innerHTML.includes(encodeURIComponent(sourceTokenKey)) || pickerEl.innerHTML.includes(sourceTokenKey), 'edit picker fallback candidates include EXT sourceTokenKey');
context.pickEditAvatar(0);
context.saveProfileEdit();
const edited = savedProfiles.at(-1);
assert.equal(edited.avatarNft.sourceTokenKey, sourceTokenKey, 'edit profile save preserves picker NFT metadata');
assert.equal(edited.avatarUrl, legacyBadUrl, 'edit profile still saves the backend-compatible primary avatarUrl');

console.log('profile_pfp_avatar_metadata=passed');




