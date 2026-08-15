import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, '..');
const target = path.join(root, 'index.html');

const cp1252 = new Map([
  ['€', 0x80], ['‚', 0x82], ['ƒ', 0x83], ['„', 0x84], ['…', 0x85], ['†', 0x86], ['‡', 0x87],
  ['ˆ', 0x88], ['‰', 0x89], ['Š', 0x8a], ['‹', 0x8b], ['Œ', 0x8c], ['Ž', 0x8e],
  ['‘', 0x91], ['’', 0x92], ['“', 0x93], ['”', 0x94], ['•', 0x95], ['–', 0x96], ['—', 0x97],
  ['˜', 0x98], ['™', 0x99], ['š', 0x9a], ['›', 0x9b], ['œ', 0x9c], ['ž', 0x9e], ['Ÿ', 0x9f],
]);
const starters = new Set(['Â', 'Ã', 'â', 'ð', 'ï']);
const marker = /[ÂÃ]|â[\u0080-\u00ff\u0100-\u017f\u0192\u02c6\u02dc\u2018-\u201e\u2020-\u2022\u2026\u2030\u2039\u203a\u20ac\u2122]|ðŸ|ï¸|\uFFFD/;

function toCp1252Bytes(text) {
  const bytes = [];
  for (const ch of text) {
    const code = ch.codePointAt(0);
    if (code <= 0xff) bytes.push(code);
    else if (cp1252.has(ch)) bytes.push(cp1252.get(ch));
    else return null;
  }
  return Buffer.from(bytes);
}

function decode(segment) {
  const bytes = toCp1252Bytes(segment);
  if (!bytes) return null;
  const decoded = bytes.toString('utf8');
  if (!decoded || decoded.includes('\uFFFD') || decoded === segment) return null;
  return decoded;
}

function repair(text) {
  const chars = [...text];
  let out = '';
  let repairs = 0;
  for (let i = 0; i < chars.length; i++) {
    if (!starters.has(chars[i])) {
      out += chars[i];
      continue;
    }
    let repaired = null;
    let used = 0;
    for (let len = Math.min(8, chars.length - i); len >= 2; len--) {
      const candidate = chars.slice(i, i + len).join('');
      const decoded = decode(candidate);
      if (decoded && !marker.test(decoded)) {
        repaired = decoded;
        used = len;
        break;
      }
    }
    if (repaired) {
      out += repaired;
      i += used - 1;
      repairs++;
    } else {
      out += chars[i];
    }
  }
  return { text: out, repairs };
}

const before = fs.readFileSync(target, 'utf8');
let pass = repair(before);
let after = pass.text;
let repairs = pass.repairs;
for (let i = 0; i < 3; i++) {
  const next = repair(after);
  after = next.text;
  repairs += next.repairs;
  if (next.repairs === 0) break;
}

if (after === before) {
  console.log('No mojibake repairs applied.');
  process.exit(0);
}
fs.writeFileSync(target, after, 'utf8');
console.log(`Repaired mojibake in ${path.relative(root, target)}.`);
console.log(`Repair replacements: ${repairs}`);
console.log(`Before bytes: ${Buffer.byteLength(before, 'utf8')}`);
console.log(`After bytes: ${Buffer.byteLength(after, 'utf8')}`);
