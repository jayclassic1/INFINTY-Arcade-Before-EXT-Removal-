import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const index = readFileSync(join(root, 'index.html'), 'utf8');

assert.ok(index.includes('function isExpectedBackendCapabilityError('), 'missing expected backend capability classifier');
assert.ok(index.includes("'getTreasuryBalance'"), 'getTreasuryBalance must be marked pending for the currently installed backend slice');
assert.ok(index.includes("'adminSweepMainToOperating'"), 'admin sweep must remain pending until backend method is live');
assert.ok(index.includes("'adminWithdrawTreasury'"), 'principal treasury withdrawal must remain pending until backend method is live');
assert.ok(index.includes("'adminWithdrawToAccountId'"), 'account-id treasury withdrawal must remain pending until backend method is live');

const handler = eventListenerBody('unhandledrejection');
assert.match(handler, /isExpectedBackendCapabilityError\(e\.reason\)/, 'unhandled rejection handler must classify expected missing backend methods before showing global banner');
assert.match(handler, /e\.preventDefault\?\.\(\)/, 'expected missing backend methods must prevent the browser unhandledrejection path');
assert.match(handler, /return;/, 'expected missing backend methods must return before creating the red/orange global banner');
assert.match(handler, /Arcade request failed\. Refresh and try again\./, 'unexpected rejections must still surface the global request banner');

const classifier = functionBody('isExpectedBackendCapabilityError');
assert.match(classifier, /OPTIONAL_BACKEND_METHODS_PENDING/, 'classifier must only suppress known pending backend capabilities');
assert.match(classifier, /has no \(query\|update\) method|no \(query\|update\) method/, 'classifier must recognize replica missing-method rejects');
assert.ok(!/return true;\s*}/.test(classifier), 'classifier must not suppress every backend/canister error');

const loadTreasuryInfo = functionBody('loadTreasuryInfo');
assert.match(loadTreasuryInfo, /backendMethodAvailable\(be,'getTreasuryBalance'\)/, 'loadTreasuryInfo must guard treasury balance before calling it');
assert.match(loadTreasuryInfo, /renderBackendSlicePending\(TREASURY_BACKEND_PENDING_COPY\)/, 'loadTreasuryInfo must render inline pending copy for missing treasury balance');

const loadTreasuryStats = functionBody('loadTreasuryStats');
assert.match(loadTreasuryStats, /backendMethodAvailable\(be2,'getTreasuryBalance'\)/, 'loadTreasuryStats must guard treasury balance before calling it');
assert.match(loadTreasuryStats, /Treasury backend pending/, 'loadTreasuryStats must degrade to inline pending status');

console.log('admin expected-missing backend validator passed');

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

function eventListenerBody(eventName) {
  const needle = `window.addEventListener('${eventName}',`;
  const start = index.indexOf(needle);
  assert.notEqual(start, -1, `missing ${eventName} listener`);
  const arrow = index.indexOf('=>', start);
  assert.notEqual(arrow, -1, `missing ${eventName} listener arrow`);
  const brace = index.indexOf('{', arrow);
  assert.notEqual(brace, -1, `missing ${eventName} listener body`);
  let depth = 0;
  for (let i = brace; i < index.length; i += 1) {
    const ch = index[i];
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return index.slice(brace + 1, i);
    }
  }
  throw new Error(`unterminated ${eventName} listener`);
}
