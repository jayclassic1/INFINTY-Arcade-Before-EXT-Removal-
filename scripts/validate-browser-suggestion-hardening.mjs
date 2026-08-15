import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const index = readFileSync(join(root, 'index.html'), 'utf8');

assert.ok(
  index.includes('function hardenTextEntryControls('),
  'missing shared hardenTextEntryControls helper for suppressing browser suggestions',
);
assert.ok(
  index.includes('MutationObserver'),
  'text-entry hardening must observe dynamic/template-rendered controls',
);
assert.ok(
  index.includes('hardenTextEntryControls(document);'),
  'text-entry hardening must run at boot for static controls',
);

const helperBody = functionBody('hardenTextEntryControls');
for (const token of [
  'autocomplete',
  'off',
  'autocorrect',
  'autocapitalize',
  'spellcheck',
  'data-browser-suggestions-hardened',
]) {
  assert.ok(helperBody.includes(token), `hardenTextEntryControls must set ${token}`);
}
assert.ok(/input\[type="text"\]/.test(helperBody), 'helper must target text inputs');
assert.ok(/input:not\(\[type\]\)/.test(helperBody), 'helper must target implicit text inputs');
assert.ok(/input\[type="url"\]/.test(helperBody), 'helper must target URL inputs');
assert.ok(/input\[type="search"\]/.test(helperBody), 'helper must target search inputs');
assert.ok(/textarea/.test(helperBody), 'helper must target textareas');
assert.ok(!/input\[type="file"\]/.test(helperBody), 'helper must not target file inputs');
assert.ok(!/input\[type="number"\]/.test(helperBody), 'helper must not target number inputs');
assert.ok(!/input\[type="checkbox"\]/.test(helperBody), 'helper must not target checkboxes');

for (const id of [
  'uploadGameId',
  'uploadGameName',
  'uploadGameDev',
  'uploadGameDesc',
  'uploadGameThumb',
  'uploadGamePrincipal',
  'uploadGamePayoutAddress',
  'colName',
  'colDescription',
  'colImageUrls',
  'extColCanisterId',
  'withdrawDestPrincipal',
  'profileNameInput',
  'nftSendDest',
  'arcadeBotInput',
]) {
  assert.ok(index.includes(`id='${id}'`) || index.includes(`id="${id}"`), `expected audited text-entry control ${id}`);
}

const directMarkupIds = [
  'uploadGameId',
  'uploadGameName',
  'uploadGameDev',
  'uploadGameDesc',
  'uploadGameThumb',
  'uploadGamePrincipal',
  'uploadGamePayoutAddress',
  'colName',
  'colDescription',
  'colImageUrls',
  'extColCanisterId',
];
for (const id of directMarkupIds) {
  const tag = tagWithId(id);
  assert.match(tag, /autocomplete=['"]off['"]/, `${id} should have direct autocomplete=off markup for admin paste fields`);
}

console.log('browser suggestion hardening validator passed');

function functionBody(name) {
  const start = index.indexOf(`function ${name}(`);
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

function tagWithId(id) {
  const idPattern = new RegExp(`<(?:input|textarea)\\b[^>]*(?:id=['"]${escapeRegExp(id)}['"])[^>]*>`, 'i');
  const match = index.match(idPattern);
  assert.ok(match, `missing input/textarea tag for ${id}`);
  return match[0];
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
