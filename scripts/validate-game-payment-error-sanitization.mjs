import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const indexPath = path.join(root, 'index.html');
const source = fs.readFileSync(indexPath, 'utf8');

let failures = 0;
function check(name, predicate) {
  if (predicate()) {
    console.log(`✅ ${name}`);
    return;
  }
  failures += 1;
  console.error(`❌ ${name}`);
}

function functionBody(name) {
  const start = source.indexOf(`function ${name}(`);
  if (start < 0) return '';
  const next = source.indexOf('\nfunction ', start + 1);
  return source.slice(start, next < 0 ? source.length : next);
}

function asyncFunctionBody(name) {
  const start = source.indexOf(`async function ${name}(`);
  if (start < 0) return '';
  const next = source.indexOf('\nasync function ', start + 1);
  const nextSync = source.indexOf('\nfunction ', start + 1);
  const candidates = [next, nextSync].filter(i => i >= 0);
  const end = candidates.length ? Math.min(...candidates) : source.length;
  return source.slice(start, end);
}

const sanitizer = functionBody('safeGamePaymentErrorMessage');
const insertCoin = asyncFunctionBody('insertCoin');
const buyGame = asyncFunctionBody('buyGame');
const tryGameDemo = asyncFunctionBody('tryGameDemo');
const forceClose = asyncFunctionBody('forceCloseArcadeSession');
const postMessageBlock = source.slice(source.indexOf("if(msgType==='arcade-request-coin')"), source.indexOf("if(msgType==='arcade-get-inventory')"));

check('game/payment sanitizer exists', () => sanitizer.length > 0);
check('sanitizer has insufficient Tokens copy', () => sanitizer.includes('Not enough Tokens. Open the wallet and convert ICP to Tokens before starting another session.'));
check('sanitizer has connect wallet copy', () => sanitizer.includes('Connect your wallet before playing.'));
check('sanitizer collapses raw backend/candid/canister blobs', () => /looksLikeRawBackendDump\(raw\)/.test(sanitizer) && sanitizer.includes('backend|canister|candid|reject'));
check('sanitizer uses short safe fallback', () => sanitizer.includes('The arcade could not complete that payment action. Try again after refreshing.'));

check('insertCoin sanitizes backend r.err', () => /safeGamePaymentErrorMessage\(r\.err/.test(insertCoin));
check('insertCoin sanitizes payment catch', () => /safeGamePaymentErrorMessage\(e/.test(insertCoin) && !insertCoin.includes("'Payment failed: '+e.message"));
check('buyGame sanitizes backend r.err and catch', () => /safeGamePaymentErrorMessage\(r\.err/.test(buyGame) && /safeGamePaymentErrorMessage\(e/.test(buyGame));
check('tryGameDemo sanitizes backend r.err and catch', () => /safeGamePaymentErrorMessage\(r\.err/.test(tryGameDemo) && /safeGamePaymentErrorMessage\(e/.test(tryGameDemo));
check('iframe arcade-request-coin sanitizes postMessage errors', () => /safeGamePaymentErrorMessage\(r\.err/.test(postMessageBlock) && /safeGamePaymentErrorMessage\(e/.test(postMessageBlock));
check('force-close session error is sanitized', () => /safeGamePaymentErrorMessage\(e/.test(forceClose));
check('native alert override sanitizes raw backend dumps', () => /window\.alert=function\(msg\)\{[\s\S]*safeGamePaymentErrorMessage\(msg/.test(source));

const forbidden = [
  "alert(r.err); return;",
  "alert('Payment failed: '+e.message)",
  "alert('Purchase failed: '+e.message)",
  "alert('Demo failed: '+e.message)",
  "reason:r.err",
  "reason:e.message",
  "escHtml(e.message||String(e))"
];
for (const token of forbidden) {
  check(`forbidden raw game/payment error pattern absent: ${token}`, () => !source.includes(token));
}

if (failures) {
  console.error(`\nGame payment error sanitization validation failed: ${failures} check(s).`);
  process.exit(1);
}
console.log('\nGame payment error sanitization validation passed.');
