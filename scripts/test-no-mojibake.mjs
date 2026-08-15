import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, '..');
const files = [path.join(root, 'index.html')];

const markerPattern = /[ÂÃ]|â[\u0080-\u00ff\u0100-\u017f\u0192\u02c6\u02dc\u2018-\u201d\u2020-\u2022\u2026\u2030\u2039\u203a\u20ac\u2122]|ðŸ|\uFFFD/g;
const findings = [];

for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  const lines = source.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const matches = [...lines[i].matchAll(markerPattern)];
    for (const match of matches) {
      findings.push(`${path.relative(root, file)}:${i + 1}: ${match[0]} :: ${lines[i].trim().slice(0, 180)}`);
    }
  }
}

assert.equal(
  findings.length,
  0,
  `mojibake markers found:\n${findings.slice(0, 80).join('\n')}${findings.length > 80 ? `\n... ${findings.length - 80} more` : ''}`,
);

console.log('mojibake detector passed');
