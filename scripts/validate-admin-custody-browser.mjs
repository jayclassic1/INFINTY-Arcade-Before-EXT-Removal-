import fs from 'node:fs';
import assert from 'node:assert/strict';

const frontend = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');

function has(source, regex) {
  return regex.test(source);
}

const legacyPrincipal = 'wncm5-gfz5o-t5lvg-fmflr-fy43v-pf26n-jxuwx-3qblr-3bn3h-xvm3k-eae';
const currentAdminPrincipal = 'fb6so-esdgb-uuuco-wjwky-qzrmj-kbljo-62sbb-vxmjq-oxwsa-d7ufn-cqe';

assert.ok(frontend.includes('ORPHAN NFT CUSTODY') || frontend.includes('ARCADE CUSTODY'), 'admin panel must expose an Arcade/Orphan NFT Custody section');
assert.ok(frontend.includes('id=\'arcadeCustodyList\'') || frontend.includes('id="arcadeCustodyList"'), 'custody section must include a rendered custody list container');
assert.ok(frontend.includes('refreshArcadeCustodyBrowser'), 'custody browser must expose a refresh/rescan action');
assert.ok(frontend.includes('renderArcadeCustodyBrowser'), 'custody browser must render grouped arcade-held NFTs');
assert.ok(frontend.includes('openArcadeCustodyReturnModal'), 'clicking a custody NFT must open a return/send flow');
assert.ok(frontend.includes('confirmArcadeCustodyReturn'), 'custody return flow must require an explicit confirmation action');
assert.ok(has(frontend, /principalToAccountHex\(S\.principalText\)/), 'custody return choice must derive the connected admin EXT account id from S.principalText');
assert.ok(frontend.includes('CURRENT CONNECTED ADMIN'), 'current admin destination choice must be visibly labeled as CURRENT CONNECTED ADMIN');
assert.ok(frontend.includes('setArcadeCustodyReturnDestination'), 'custody return modal must require an explicit destination choice before transfer');
assert.ok(frontend.includes('Choose current admin'), 'custody return modal must prompt the admin to choose the current admin destination');
assert.ok(frontend.includes('No destination chosen yet'), 'custody return modal must start without an implicit destination selected');
assert.ok(!has(frontend, /id="arcadeCustodyReturnAccount"\s+value="\$\{escHtml\(defaultAccount\)\}"/), 'custody return modal must not silently pre-fill the current admin destination');
assert.ok(frontend.includes('copyCurrentAdminCustodyAccount'), 'current admin account id must be copyable');
assert.ok(frontend.includes(currentAdminPrincipal), 'current/new website admin principal must remain authorized/visible in admin configuration');
assert.ok(has(frontend, /LEGACY_ADMIN_PRINCIPAL\s*=\s*['"]wncm5-gfz5o-t5lvg-fmflr-fy43v-pf26n-jxuwx-3qblr-3bn3h-xvm3k-eae['"]/), 'legacy admin principal must be isolated under a clearly named legacy constant');
assert.ok(!has(frontend, new RegExp(`heldExtReturnAccount[\\s\\S]{0,900}${legacyPrincipal}`)), 'manual recovery UI must not default return sends to the legacy principal/account');
assert.ok(!has(frontend, /adminReturnHeldExtNftFromUi[\s\S]{0,1400}JAY_PRINCIPAL/), 'admin return flow must not use JAY_PRINCIPAL as a destination default');
assert.ok(!has(frontend, /adminReturnHeldExtNftFromUi[\s\S]{0,900}currentConnectedAdminExtAccountId\(\)/), 'manual admin return flow must not auto-fill blank destination from current admin');
assert.ok(frontend.includes('Custody returns never auto-default to admin'), 'manual admin return flow must require exact explicit destination copy');
assert.ok(frontend.includes('Custody sends do not auto-default'), 'custody warning must explain sends require explicit destination choice');
assert.ok(!frontend.includes('Defaults send-to-me actions'), 'custody UI must not describe send-to-me/current-admin as a default');
assert.ok(!has(frontend, /default[s]?\s+send-to-me/i), 'custody UI must reject stale default send-to-me wording');
assert.ok(frontend.includes('Every transfer requires choosing the destination account first'), 'custody section copy must emphasize explicit destination choice');
assert.ok(has(frontend, /tokens\(getArcadeAccountId\(\)\)/), 'custody browser must discover held EXT tokens via public EXT tokens(arcadeAccountId) calls');
assert.ok(frontend.includes('adminReturnHeldExtNft'), 'custody send flow must use the existing backend adminReturnHeldExtNft method');
assert.ok(has(frontend, /64-character EXT account id/i), 'send flow must validate/prompt for a 64-character EXT account id');
assert.ok(frontend.includes('listing/escrow record'), 'custody cards must surface whether a listing/escrow record exists when available');
assert.ok(frontend.includes('No arcade-held EXT NFTs found'), 'custody browser must have an empty state');
assert.ok(frontend.includes('Unable to scan arcade custody'), 'custody browser must have an error state');
assert.ok(frontend.includes('formatExtVariantError'), 'custody browser must format EXT variant errors instead of rendering [object Object]');
assert.ok(!frontend.includes("String(result.err):'EXT tokens(accountId) failed'"), 'custody scan must not stringify EXT error variants into [object Object]');

console.log('validate-admin-custody-browser: ok');
