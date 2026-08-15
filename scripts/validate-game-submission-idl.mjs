import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const index = readFileSync(join(root, 'index.html'), 'utf8');
const backend = readFileSync(join(root, 'backend', 'main.mo'), 'utf8');
const did = readFileSync(join(root, 'backend', '.build', 'arcade_backend', 'arcade_backend.did'), 'utf8');

const backendFields = extractMotokoTypeFields(backend, 'GameSubmission');
const didFields = extractDidRecordFields(did, 'GameSubmission');
const frontendFields = extractFrontendIdlFields(index, 'GameSubmission');

assert.deepEqual(didFields, backendFields, 'generated backend DID GameSubmission must match backend/main.mo lean schema');
assert.deepEqual(frontendFields, backendFields, 'frontend GameSubmission IDL must match backend lean schema exactly so adminGetAllGames decodes live responses');

for (const uiOnly of ['paysTickets', 'screenshots', 'category', 'tokenCost', 'scoringMode']) {
  assert.ok(!frontendFields.includes(uiOnly), `frontend IDL must not require UI-only field ${uiOnly}`);
}

assert.ok(index.includes('function normalizeGameSubmission('), 'frontend must normalize lean backend GameSubmission records after decode');
const normalizeBody = functionBody(index, 'normalizeGameSubmission');
assert.ok(/paysTickets\s*:\s*g\.paysTickets\s*!==\s*false/.test(normalizeBody), 'normalizer must default missing paysTickets to true');
assert.ok(/screenshots\s*:\s*Array\.isArray\(g\.screenshots\)\?g\.screenshots:\[\]/.test(normalizeBody), 'normalizer must default missing screenshots to []');
assert.ok(/tokenCost\s*:\s*Number\(g\.tokenCost\)\|\|1/.test(normalizeBody), 'normalizer must default missing tokenCost to 1');
assert.ok(/scoringMode\s*:\s*g\.scoringMode\|\|'best-of'/.test(normalizeBody), 'normalizer must default missing scoringMode to best-of');
assert.ok(/gameCategory\s*:\s*g\.category\|\|''/.test(normalizeBody), 'normalizer must default missing category to empty string');

const getSubmissionsBody = functionBody(index, 'getSubmissionsAsync');
assert.ok(/games\.map\(normalizeGameSubmission\)/.test(getSubmissionsBody), 'getSubmissionsAsync must normalize decoded games through one shared normalizer');

const renderAdminBody = functionBody(index, 'renderGameAdminList');
assert.ok(/raw\.map\(normalizeGameSubmission\)/.test(renderAdminBody), 'renderGameAdminList must normalize decoded admin games through one shared normalizer');

const ticketFundingBody = functionBody(index, 'loadTicketReserveFundingAdmin');
assert.ok(/games\|\|\[\]\)\.map\(normalizeGameSubmission\)/.test(ticketFundingBody), 'loadTicketReserveFundingAdmin must normalize decoded admin games before using UI-only fields');

console.log('game submission IDL compatibility validator passed');

function extractMotokoTypeFields(source, typeName) {
  const marker = `type ${typeName} = {`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `missing Motoko type ${typeName}`);
  const body = source.slice(start + marker.length, source.indexOf('\n  };', start));
  return body.split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('//'))
    .map((line) => line.split(':')[0].trim())
    .sort();
}

function extractDidRecordFields(source, typeName) {
  const start = source.indexOf(`type ${typeName} =`);
  assert.notEqual(start, -1, `missing DID type ${typeName}`);
  const recordStart = source.indexOf('record {', start);
  assert.notEqual(recordStart, -1, `missing DID record for ${typeName}`);
  const end = source.indexOf('\n };', recordStart);
  assert.notEqual(end, -1, `unterminated DID record for ${typeName}`);
  return source.slice(recordStart + 'record {'.length, end)
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => line.split(':')[0].trim())
    .sort();
}

function extractFrontendIdlFields(source, typeName) {
  const marker = `const ${typeName}=IDL.Record({`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `missing frontend IDL ${typeName}`);
  const open = source.indexOf('{', start);
  const close = findMatchingBrace(source, open);
  return source.slice(open + 1, close)
    .split('\n')
    .flatMap((line) => line.split(','))
    .map((part) => part.trim())
    .filter((part) => /^[A-Za-z_$][\w$]*\s*:/.test(part))
    .map((part) => part.split(':')[0].trim())
    .sort();
}

function functionBody(source, name) {
  let start = source.indexOf(`async function ${name}(`);
  if (start === -1) start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `missing function ${name}`);
  const open = source.indexOf('{', start);
  const close = findMatchingBrace(source, open);
  return source.slice(open + 1, close);
}

function findMatchingBrace(source, open) {
  assert.notEqual(open, -1, 'missing opening brace');
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  throw new Error('unterminated brace block');
}
