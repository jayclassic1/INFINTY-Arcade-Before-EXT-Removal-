import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import assert from 'node:assert/strict';

const root = process.cwd();
const frontend = readFileSync(join(root, 'index.html'), 'utf8');

function extractFunction(source, name) {
  const start = source.indexOf(`async function ${name}(`);
  assert.notEqual(start, -1, `${name} function missing`);
  const nextFunction = source.indexOf('\nasync function ', start + 1);
  return source.slice(start, nextFunction === -1 ? source.length : nextFunction);
}

const claimCreatorEarnings = extractFunction(frontend, 'claimCreatorEarnings');

assert.match(
  claimCreatorEarnings,
  /const\s+be\s*=\s*await\s+getBackendActor\(true\)\s*;/,
  'claimCreatorEarnings must use the authenticated backend actor for claimRoyalties()'
);

assert.match(
  frontend,
  /Total claimable creator \/ seller ICP/i,
  'Creator/Seller Earnings dashboard must show the combined creator + seller claimable total'
);

console.log('Claim auth fix validation PASSED (2/2)');
