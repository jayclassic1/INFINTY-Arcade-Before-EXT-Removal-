import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const html = readFileSync(join(root, 'index.html'), 'utf8');

const failures = [];
const expect = (condition, message) => {
  if (!condition) failures.push(message);
};

function parseZIndex(styleText) {
  const match = /z-index\s*:\s*(\d+)/i.exec(styleText || '');
  return match ? Number(match[1]) : null;
}

function getElementStyleById(source, id) {
  const tagMatch = new RegExp(`<[^>]+id=['\"]${id}['\"][^>]*>`, 'i').exec(source);
  if (!tagMatch) return '';
  const styleMatch = /style=['\"]([^'\"]*)['\"]/i.exec(tagMatch[0]);
  return styleMatch ? styleMatch[1] : '';
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function getCreatedModalCssText(source, id) {
  const match = new RegExp(`([A-Za-z_$][\\w$]*)\\.id\\s*=\\s*['\"]${escapeRegExp(id)}['\"]\\s*;[\\s\\S]{0,240}?\\1\\.style\\.cssText\\s*=\\s*['\"]([^'\"]*)['\"]`, 'i').exec(source);
  return match ? match[2] : '';
}

function getAssignedFunctionBody(source, assignmentPattern) {
  const match = assignmentPattern.exec(source);
  if (!match) return null;
  const open = source.indexOf('{', match.index);
  return readBalancedBlock(source, open);
}

function getDeclaredFunction(source, declarationPattern) {
  const match = declarationPattern.exec(source);
  if (!match) return null;
  const open = source.indexOf('{', match.index + match[0].length);
  return { params: match[1] || '', body: readBalancedBlock(source, open) };
}

function readBalancedBlock(source, open) {
  if (open < 0 || source[open] !== '{') return '';
  let depth = 0;
  let quote = null;
  let escaped = false;
  let templateDepth = 0;
  for (let i = open; i < source.length; i += 1) {
    const ch = source[i];
    const next = source[i + 1];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (quote === '`' && ch === '$' && next === '{') {
        templateDepth += 1;
        depth += 1;
        i += 1;
      } else if (quote === '`' && ch === '}' && templateDepth > 0) {
        templateDepth -= 1;
        depth -= 1;
      } else if (ch === quote && templateDepth === 0) {
        quote = null;
      }
      continue;
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      quote = ch;
      continue;
    }
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  return '';
}

const mobileWithdrawBody = getAssignedFunctionBody(html, /window\.mobileWithdraw\s*=\s*function\s*\(/);
expect(Boolean(mobileWithdrawBody), 'window.mobileWithdraw function must exist');
expect(/mobileWdAmt/.test(mobileWithdrawBody || ''), 'mobileWithdraw must read #mobileWdAmt');
expect(/mobileWdAddr/.test(mobileWithdrawBody || ''), 'mobileWithdraw must read #mobileWdAddr');
expect(/mobileWdRes/.test(mobileWithdrawBody || ''), 'mobileWithdraw must target #mobileWdRes');
expect(/withdrawIcp\s*\(\s*\{[\s\S]*(amount|amt)[\s\S]*(destination|dest)[\s\S]*(resultElement|resultId|result)/.test(mobileWithdrawBody || ''), 'mobileWithdraw must pass mobile amount, destination, and result target into withdrawIcp');

const withdraw = getDeclaredFunction(html, /async\s+function\s+withdrawIcp\s*\(([^)]*)\)/);
const withdrawParams = withdraw?.params || '';
const withdrawBody = withdraw?.body || '';
expect(Boolean(withdraw), 'withdrawIcp function must exist');
expect(withdrawParams.trim().length > 0, 'withdrawIcp must accept optional input options while preserving desktop default');
expect(/amount/.test(withdrawBody) && /destination/.test(withdrawBody), 'withdrawIcp must consume optional amount and destination inputs');
expect(/result(Element|El|Id)?/.test(withdrawBody) && /withdrawRes/.test(withdrawBody), 'withdrawIcp must support optional result target and keep desktop #withdrawRes fallback');
expect(/showStatus/.test(withdrawBody) && /fail/.test(withdrawBody), 'withdrawIcp validation/errors must surface in the selected result area');
expect(!/return\s+alert\s*\(/.test(withdrawBody), 'withdrawIcp validation should surface status in the selected result area, not only alert');

const update = getDeclaredFunction(html, /function\s+update\s*\(([^)]*)\)/);
const updateBody = update?.body || '';
expect(Boolean(update), 'update() function must exist');
expect(/typeof\s+updateMobileWallet\s*===\s*['"]function['"][\s\S]*updateMobileWallet\s*\(\s*\)/.test(updateBody), 'update() must safely sync mobile wallet state via updateMobileWallet()');

const mobileOverlayStyle = getElementStyleById(html, 'mobileOverlay');
const mobileOverlayZ = parseZIndex(mobileOverlayStyle);
const arcadeConnectModalZ = parseZIndex(getCreatedModalCssText(html, 'arcadeConnectModal'));
expect(mobileOverlayZ !== null, '#mobileOverlay must define a z-index');
expect(arcadeConnectModalZ !== null, '#arcadeConnectModal must define a z-index when showConnect() creates it');
expect(arcadeConnectModalZ > mobileOverlayZ, '#arcadeConnectModal z-index must be above #mobileOverlay so mobile Connect / Create is visible');
expect(/overflow-x\s*:\s*hidden/i.test(mobileOverlayStyle), '#mobileOverlay must hide horizontal overflow on phone viewports');
expect(/width\s*:\s*100vw/i.test(mobileOverlayStyle), '#mobileOverlay must be constrained to 100vw width');
expect(/max-width\s*:\s*100vw/i.test(mobileOverlayStyle), '#mobileOverlay must cap max-width at 100vw');
expect(/box-sizing\s*:\s*border-box/i.test(mobileOverlayStyle), '#mobileOverlay must use border-box sizing');
expect(/\.mobile-shell\s*\{[^}]*width\s*:\s*min\(100%,400px\)[^}]*padding\s*:\s*clamp\(10px,4vw,20px\)[^}]*box-sizing\s*:\s*border-box[^}]*max-width\s*:\s*100vw/is.test(html), '.mobile-shell must fit within the viewport with responsive horizontal padding');
expect(/\.mob-card\s*\{[^}]*min-width\s*:\s*0[^}]*max-width\s*:\s*100%/is.test(html), '.mob-card must be allowed to shrink within the mobile shell');
expect(/\.mobile-shrink-row\s*\{[^}]*min-width\s*:\s*0/is.test(html), 'mobile inline rows must have a shrink-safe class');
expect(/#mobileNftGrid\s*\{[^}]*min-width\s*:\s*0[^}]*max-width\s*:\s*100%/is.test(html), '#mobileNftGrid must be constrained to the mobile card width');

const mobileConnectTag = /<button\b[^>]*id=['"]mobileConnectBtn['"][^>]*>/i.exec(html)?.[0] || '';
expect(Boolean(mobileConnectTag), '#mobileConnectBtn must exist');
expect(/onclick=['"]showConnect\(\)['"]/i.test(mobileConnectTag), '#mobileConnectBtn must still call showConnect()');

const mobileNftReceiveIdx = html.indexOf("id='mobileNftReceivePrincipal'");
const mobileNftReceiveBlock = mobileNftReceiveIdx >= 0 ? html.slice(Math.max(0, mobileNftReceiveIdx - 700), mobileNftReceiveIdx + 900) : '';
const mobileNftReceiveTag = /<div\b[^>]*id=['"]mobileNftReceivePrincipal['"][^>]*>/i.exec(html)?.[0] || '';
const mobileNftCopyButtonTag = /<button\b[^>]*id=['"]mobileCopyNftPrincipal['"][^>]*>/i.exec(html)?.[0] || '';
expect(Boolean(mobileNftReceiveTag), 'mobile wallet must include a dedicated NFT receive principal display');
expect(/NFT RECEIVE PRINCIPAL/i.test(mobileNftReceiveBlock), 'mobile NFT receive area must be labeled as NFT receive principal');
expect(!/DEPOSIT ADDRESS/i.test(mobileNftReceiveBlock), 'mobile NFT receive area wording must be distinct from ICP deposit address');
expect(Boolean(mobileNftCopyButtonTag), 'mobile NFT receive area must include a copy principal button');
expect(/onclick=['"]copyPrincipal\(\)['"]/i.test(mobileNftCopyButtonTag), 'mobile NFT copy button must reuse copyPrincipal() behavior');
expect(/title=['"][^'"]*NFT receive principal/i.test(mobileNftReceiveTag), 'mobile NFT principal display should explain it is for NFT receives');
expect(/mobileNftReceivePrincipal[\s\S]{0,220}S\.principalText|S\.principalText[\s\S]{0,220}mobileNftReceivePrincipal/.test(html), 'mobile wallet sync must populate the NFT receive principal from S.principalText');

const mobileNftButtonTag = /<button\b[^>]*onclick=['"]([^'"]*)['"][^>]*>Scan NFTs<\/button>/i.exec(html)?.[0] || '';
const mobileNftButtonOnclick = /<button\b[^>]*onclick=['"]([^'"]*)['"][^>]*>Scan NFTs<\/button>/i.exec(html)?.[1] || '';
expect(Boolean(mobileNftButtonTag), 'mobile Scan NFTs button must exist');
const mobileScanHelperBody = getAssignedFunctionBody(html, /window\.mobileScanWalletNfts\s*=\s*async\s+function\s*\(/) || '';
expect(/scanAndCacheWalletNfts\s*\(\s*true\s*\)/.test(mobileNftButtonOnclick) || /scanAndCacheWalletNfts\s*\(\s*true\s*\)/.test(mobileScanHelperBody), 'mobile Scan NFTs button must call the shared direct wallet NFT scan flow');
expect(!/loadWalletNfts\s*\(/.test(mobileNftButtonOnclick + mobileScanHelperBody), 'mobile Scan NFTs button must not depend on loadWalletNfts or desktop #walletNftGrid');
expect(!/background\s*:\s*none/i.test(mobileNftButtonTag), 'mobile Scan NFTs button must not use transparent background:none styling');
expect(/linear-gradient|background\s*:\s*#[0-9a-f]{3,6}|background\s*:\s*var\(/i.test(mobileNftButtonTag), 'mobile Scan NFTs button must have a visible solid/gradient active background');
expect(/Scanning NFTs/i.test(mobileNftButtonOnclick + mobileScanHelperBody), 'mobile Scan NFTs loading state must clearly label scanning progress');
const sharedWalletScan = getDeclaredFunction(html, /async\s+function\s+scanAndCacheWalletNfts\s*\(([^)]*)\)/);
expect(Boolean(sharedWalletScan), 'scanAndCacheWalletNfts shared wallet NFT scan helper must exist');
expect(/scanOwnedWalletNfts\s*\(/.test(sharedWalletScan?.body || ''), 'scanAndCacheWalletNfts must directly call scanOwnedWalletNfts');
expect(/_ownedWalletNftsCache/.test(sharedWalletScan?.body || ''), 'scanAndCacheWalletNfts must update or validate the shared owned-wallet NFT cache');
const scanOwnedBody = getDeclaredFunction(html, /async\s+function\s+scanOwnedWalletNfts\s*\(([^)]*)\)/)?.body || '';
expect(/_ownedWalletNftScanState/.test(html), 'wallet NFT scan must retain a scan state for partial/unavailable collection results');
expect(/failures\.push/.test(scanOwnedBody) && /successes\.push/.test(scanOwnedBody), 'scanOwnedWalletNfts must collect successful and failed collection paths instead of collapsing on one failure');
expect(/getOwnedWalletNftScanNotice/.test(html), 'mobile wallet scan must expose a non-fatal partial/unavailable collection notice');
const desktopWalletBody = getDeclaredFunction(html, /async\s+function\s+loadWalletNfts\s*\(([^)]*)\)/)?.body || '';
expect(/scanAndCacheWalletNfts\s*\(\s*true\s*\)/.test(desktopWalletBody), 'desktop loadWalletNfts must consume the same shared wallet NFT scan/cache flow');
const mobileNftsBody = getAssignedFunctionBody(html, /window\.updateMobileNfts\s*=\s*function\s*\(/);
expect(Boolean(mobileNftsBody), 'window.updateMobileNfts function must exist');
expect(/items\s*=\s*null/.test(mobileNftsBody || '') || /Array\.isArray\s*\(\s*items\s*\)/.test(mobileNftsBody || ''), 'updateMobileNfts must accept a returned NFT list while retaining cache fallback');
expect(/_ownedWalletNftsCache[\s\S]*items/.test(mobileNftsBody || ''), 'updateMobileNfts must retain the shared wallet NFT scan cache fallback');
expect(/showWalletNftDetail\s*\(/.test(mobileNftsBody || ''), 'mobile NFT tiles must open the existing wallet NFT detail/send modal');
expect(/JSON\.stringify\s*\(\s*JSON\.stringify\s*\(\s*n\s*\)\s*\)/.test(mobileNftsBody || ''), 'mobile NFT detail clicks must pass the same JSON payload shape as desktop wallet tiles');
expect(/cursor\s*:\s*pointer/.test(mobileNftsBody || ''), 'mobile NFT tiles should visibly behave as tappable controls');
expect(/role=["']button["']/.test(mobileNftsBody || '') && /tabindex=["']0["']/.test(mobileNftsBody || ''), 'mobile NFT tiles must expose button semantics for tap/keyboard activation');
expect(/openWalletNftDetailFromMobile\s*\(/.test(mobileNftsBody || ''), 'mobile NFT tile activation must route through a mobile-safe detail opener');
expect(/resolveWalletNftMediaUrl\s*\(\s*n\s*\)/.test(mobileNftsBody || ''), 'mobile NFT tiles must resolve media from NFT metadata fields, not only n.imageUrl');
expect(/mobile-wallet-nft-fallback/.test(mobileNftsBody || ''), 'mobile NFT tiles must render a text fallback block instead of only a giant question mark');
expect(/white-space\s*:\s*normal/.test(mobileNftsBody || '') && /overflow-wrap\s*:\s*anywhere/.test(mobileNftsBody || ''), 'mobile NFT labels must wrap safely instead of clipping unreadably on phone');
const mediaResolver = getDeclaredFunction(html, /function\s+resolveWalletNftMediaUrl\s*\(([^)]*)\)/);
expect(Boolean(mediaResolver), 'resolveWalletNftMediaUrl helper must exist');
expect(/imageUrl/.test(mediaResolver?.body || '') && /thumbnail/.test(mediaResolver?.body || '') && /metadata/.test(mediaResolver?.body || '') && /url/.test(mediaResolver?.body || ''), 'resolveWalletNftMediaUrl must inspect imageUrl, thumbnail/media/url, and metadata fields');
const mobileDetailOpener = getDeclaredFunction(html, /function\s+openWalletNftDetailFromMobile\s*\(([^)]*)\)/);
expect(Boolean(mobileDetailOpener), 'openWalletNftDetailFromMobile helper must exist');
expect(/showWalletNftDetail\s*\(/.test(mobileDetailOpener?.body || '') && /walletNftModal/.test(mobileDetailOpener?.body || ''), 'mobile detail opener must open the wallet send modal and leave a visible modal target');

const knownExtBody = /const\s+KNOWN_EXT_COLLECTIONS\s*=\s*\[([\s\S]*?)\];/.exec(html)?.[1] || '';
for (const [name, id] of [
  ['Wumbros', 'ckbgq-4yaaa-aaaak-qi2xq-cai'],
  ['Motoko Pals', 'hhce5-bqaaa-aaaak-qtt3q-cai'],
  ['Motoko Ghosts', 'oeee4-qaaaa-aaaak-qaaeq-cai'],
  ['Poked Bots', 'bzsui-sqaaa-aaaah-qce2a-cai'],
]) {
  expect(knownExtBody.includes(name) && knownExtBody.includes(id), `KNOWN_EXT_COLLECTIONS must retain ${name} (${id})`);
}

const collectionGridStyle = getElementStyleById(html, 'nftCollectionGrid');
expect(/repeat\(auto-fit,minmax\(min\(150px,100%\),1fr\)\)/i.test(collectionGridStyle), '#nftCollectionGrid must use a responsive mobile-safe grid template');
expect(/padding\s*:\s*0\s+clamp\(8px,3vw,30px\)/i.test(collectionGridStyle), '#nftCollectionGrid must use responsive horizontal padding');
expect(/justify-items\s*:\s*center/i.test(collectionGridStyle), '#nftCollectionGrid must center cards inside responsive columns');
expect(/max-width\s*:\s*100%/i.test(collectionGridStyle), '#nftCollectionGrid must not exceed the phone viewport');

const collectionBody = getDeclaredFunction(html, /async\s+function\s+renderCollection\s*\(([^)]*)\)/)?.body || '';
expect(/loadBackendProfileCollectionNfts\s*\(/.test(collectionBody), 'renderCollection must merge the backend/profile collection fallback');
expect(/mergeCollectionNfts\s*\(/.test(collectionBody), 'renderCollection must deduplicate merged collection NFT sources');
expect(/catch\s*\([^)]*\)\s*\{\s*console\.warn\(['"]Backend collection fallback/i.test(collectionBody), 'backend collection fallback must be caught without blocking the primary scan');
expect(/No supported NFTs found/i.test(collectionBody), 'collection empty state must distinguish a supported scan miss from ownership absence');
expect(/Supported Collections/i.test(collectionBody) && /Scan/i.test(collectionBody), 'collection empty copy must point users to Supported Collections and Scan');
expect(/Manual Listing/i.test(collectionBody), 'collection empty copy must mention the manual listing path');
expect(/showView\(\\?['"]nft-upload\\?['"]\)/.test(collectionBody) && /switchNftTab\(\\?['"]existing\\?['"]\)/.test(collectionBody), 'collection empty copy must point to the existing-NFT manual listing flow');
expect(/width\s*:\s*min\(120px,100%\)/i.test(collectionBody), 'collection cards must be mobile-safe instead of fixed 120px wide');

const backendFallback = getDeclaredFunction(html, /async\s+function\s+loadBackendProfileCollectionNfts\s*\(([^)]*)\)/);
expect(Boolean(backendFallback), 'loadBackendProfileCollectionNfts helper must exist');
expect(/typeof\s+be\.getMyCollection\s*!==\s*['"]function['"]/.test(backendFallback?.body || '') || /typeof\s+be\.getMyCollection\s*===\s*['"]function['"]/.test(backendFallback?.body || ''), 'backend fallback helper must guard getMyCollection before calling it because the bundled IDL may omit it');
expect(/getMyCollection\s*\(/.test(backendFallback?.body || ''), 'backend fallback helper may call getMyCollection(principal) only after the guard');
expect(/source\s*:\s*['"]backend-profile['"]/.test(backendFallback?.body || ''), 'backend fallback NFTs must carry a backend-profile source marker');
expect(/canisterId/.test(backendFallback?.body || '') && /tokenId/.test(backendFallback?.body || ''), 'backend fallback NFTs must normalize canister/token fields');

const mergeHelper = getDeclaredFunction(html, /function\s+mergeCollectionNfts\s*\(([^)]*)\)/);
expect(Boolean(mergeHelper), 'mergeCollectionNfts helper must exist');
expect(/dedupeCollectionNftKey\s*\(/.test(mergeHelper?.body || ''), 'merge helper must deduplicate by a collection NFT key');
expect(/canisterId/.test(html) && /tokenId/.test(html) && /sourceTokenKey/.test(html), 'collection NFT dedupe key must include canister/token/source identity fields');

if (failures.length) {
  console.error('Mobile wallet access validation failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log('Mobile wallet access validation passed');
