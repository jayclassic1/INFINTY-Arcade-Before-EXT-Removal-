import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const index = readFileSync(join(root, 'index.html'), 'utf8');

assert.ok(index.includes('function isAssetCanisterPermissionError('), 'missing asset-canister permission detector');
assert.ok(index.includes('function safeAssetCanisterErrorMessage('), 'missing asset-canister UI sanitizer');
assert.ok(index.includes('Prepare/Commit permission'), 'sanitized permission message must tell admins what to grant');
assert.ok(index.includes('configured deploy identity'), 'sanitized permission message must suggest deploy identity fallback');

const detector = functionBody('isAssetCanisterPermissionError');
for (const token of [
  'Caller does not have Prepare permission',
  'Unauthorized',
  'canister_reject',
  'IC0406',
  'create_batch',
  'create_chunk',
  'commit_batch',
  'delete_asset',
]) {
  assert.ok(detector.includes(token), `asset permission detector must recognize ${token}`);
}

const sanitizer = functionBody('safeAssetCanisterErrorMessage');
assert.ok(sanitizer.includes('isAssetCanisterPermissionError'), 'asset sanitizer must use permission detector');
assert.ok(sanitizer.includes('raw IC response was logged to the console'), 'asset sanitizer must replace raw dumps with developer-console guidance');
assert.ok(!/return\s+raw\s*;/.test(sanitizer), 'asset sanitizer must not return raw error objects/messages unbounded');

for (const name of ['handleHostedThumbnailUpload', 'handleGameScreenshotUploads']) {
  const body = functionBody(name);
  assert.ok(body.includes('safeUploadErrorMessage'), `${name} must sanitize hosted asset upload errors`);
  assert.ok(!/(innerHTML|textContent|alert)\s*[^;]*(e\.message|\(e\.message\|\|e\)|String\(e\))/s.test(body), `${name} must not display raw asset upload errors`);
}

for (const name of ['uploadGameToChain', 'deleteGameFromChain', 'adminCreateCollection']) {
  const body = functionBody(name);
  assert.ok(body.includes('safeAssetCanisterErrorMessage'), `${name} must sanitize game asset canister errors`);
  assert.ok(/console\.error/.test(body), `${name} must preserve developer console logging`);
}

const uploadBody = functionBody('uploadGameToChain');
assert.ok(!/Upload failed:\s*'\s*\+\s*e\.message/.test(uploadBody), 'uploadGameToChain must not render raw e.message');
assert.ok(!/Upload failed:\s*'\s*\+\s*\(e\.message\|\|e\)/.test(uploadBody), 'uploadGameToChain must not render raw (e.message||e)');

const deleteBody = functionBody('deleteGameFromChain');
assert.ok(!/Delete failed:\s*'\s*\+\s*e\.message/.test(deleteBody), 'deleteGameFromChain must not render raw e.message');
assert.ok(!/Delete failed:\s*'\s*\+\s*\(e\.message\|\|e\)/.test(deleteBody), 'deleteGameFromChain must not render raw (e.message||e)');

const collectionBody = functionBody('adminCreateCollection');
assert.ok(!/Upload failed:\s*'\s*\+\s*\(e\.message\|\|e\)/.test(collectionBody), 'collection image zip upload must not render raw (e.message||e)');
assert.ok(!/JSZip:'\s*\+/.test(collectionBody), 'collection image zip upload must not append raw debugging internals to user-facing status');

console.log('upload UI soft-audit validator passed');

function functionBody(name) {
  let start = index.indexOf(`async function ${name}(`);
  if (start === -1) start = index.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `missing function ${name}`);
  const brace = index.indexOf('{', start);
  assert.notEqual(brace, -1, `missing opening brace for ${name}`);
  let depth = 0;
  for (let i = brace; i < index.length; i += 1) {
    const ch = index[i];
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return index.slice(brace + 1, i);
    }
  }
  throw new Error(`unterminated function ${name}`);
}
