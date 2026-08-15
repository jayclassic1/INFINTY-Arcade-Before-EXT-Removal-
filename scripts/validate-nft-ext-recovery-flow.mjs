import fs from 'node:fs';
import assert from 'node:assert/strict';

const frontend = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const backend = fs.readFileSync(new URL('../backend/main.mo', import.meta.url), 'utf8');

const CURRENT_BACKEND_EXT_ACCOUNT = '2b239054e41a561e39350c1e86fa53f97ba4acf8b40600574ea965ac11164ebb';
const STALE_BACKEND_EXT_ACCOUNT = '1aa0c0d0c0d19fa62dc61065faea9c82d5e88a0af26ed8ba159cd0b7689ebe15';

function has(source, regex) {
  return regex.test(source);
}

assert.ok(backend.includes(CURRENT_BACKEND_EXT_ACCOUNT), 'backend must use the current backend EXT account id');
assert.ok(!backend.includes(`SELF_ACCOUNT_ID : Text = "${STALE_BACKEND_EXT_ACCOUNT}"`), 'backend must not keep the stale SELF_ACCOUNT_ID constant');
assert.ok(has(backend, /func extHoldMismatchMessage\(accountId : Text\) : Text/), 'backend should centralize held-EXT mismatch copy');
assert.ok(has(backend, /adminRegisterHeldExtNft\s*\(/), 'backend must expose adminRegisterHeldExtNft');
assert.ok(has(backend, /adminRegisterHeldNft\s*\(/), 'legacy adminRegisterHeldNft must remain as a compatible entrypoint');
assert.ok(has(backend, /adminRegisterHeldNft[\s\S]*registerHeldExtNftImpl/), 'legacy adminRegisterHeldNft must use the held-EXT registration path');
assert.ok(has(backend, /adminReturnHeldExtNft\s*\(\s*canisterId : Text,\s*extTokenId : Text,\s*toAccountId : Text/), 'backend must expose adminReturnHeldExtNft with EXT account-id recipient');
assert.ok(has(backend, /Text\.size\(Text\.trim\(toAccountId, #char ' '\)\) == 0/), 'adminReturnHeldExtNft must reject blank recipient account ids');
assert.ok(has(backend, /to = #address\(toAccountId\)/), 'adminReturnHeldExtNft must transfer to EXT account id');

assert.ok(frontend.includes('adminRegisterHeldExtNft'), 'frontend backend IDL must expose adminRegisterHeldExtNft');
assert.ok(frontend.includes('adminReturnHeldExtNft'), 'frontend backend IDL must expose adminReturnHeldExtNft');
assert.ok(frontend.includes('adminDiagnoseHeldExtNft'), 'frontend must provide admin diagnose helper');
assert.ok(frontend.includes('adminRegisterHeldExtNftFromUi'), 'frontend must provide admin register helper');
assert.ok(frontend.includes('adminReturnHeldExtNftFromUi'), 'frontend must provide admin return helper');
assert.ok(frontend.includes('Verify & List · Free'), 'admin listing button/copy must show free path');
assert.ok(has(frontend, /requireListingActorSession\s*\(/), 'frontend must guard listing flow with an authenticated actor session before transfer');
assert.ok(frontend.includes('Admin recovery needed') || frontend.includes('Recovery state'), 'post-transfer listing/confirm failure must direct admins to recovery instead of promising return');
assert.ok(!frontend.includes('Verify & List · 2 Tokens</button>'), 'static listing button must not hardcode 2 Tokens for admin path');
assert.ok(!has(frontend, /NFT returned to your wallet\./) || has(frontend, /if\(retResult && retResult\.ok\)[\s\S]*NFT returned to your wallet\./), 'frontend must only claim return succeeded inside an explicit ok branch when that copy exists');
assert.ok(has(frontend, /Recovery state[\s\S]*Pending listing ID:[\s\S]*Full token ID:[\s\S]*pending_escrow/), 'frontend must show exact pending recovery state when transfer confirmation fails');
assert.ok(has(frontend, /window\._lastListingId\s*=\s*null[\s\S]*submitExistingNft\(listingActor\)/), 'verifyAndListNft must clear stale _lastListingId before each listing attempt');
assert.ok(has(frontend, /const listingResult\s*=\s*await submitExistingNft\(listingActor\)/), 'verifyAndListNft must read explicit submitExistingNft result');
assert.ok(has(frontend, /if\(!listingResult\s*\|\|\s*!listingResult\.ok\)[\s\S]*throw \(listingResult && listingResult\.error\) \|\| new Error/), 'verifyAndListNft must throw on explicit submitExistingNft failure after transfer');
assert.ok(has(frontend, /return \{ok:true,listingId:listResult\.ok\}/), 'submitExistingNft must return explicit success with listingId');
assert.ok(has(frontend, /catch\(e\)\{[\s\S]*return \{ok:false,error:e\}/), 'submitExistingNft catch must return explicit failure instead of silently swallowing errors');
assert.ok(!has(frontend, /await submitExistingNft\(listingActor\);\s*const listingId=window\._lastListingId/), 'verifyAndListNft must not trust stale window._lastListingId after submitExistingNft');

console.log('validate-nft-ext-recovery-flow: ok');
