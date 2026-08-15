#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const source = readFileSync(join(process.cwd(), 'games', 'swing-blade', 'index.html'), 'utf8');
const checks = [];
function check(name, pass) {
  checks.push({ name, pass: !!pass });
}

check('start helper exists in visible launch UI', /id=["']startHint["']/.test(source));
check('start button describes helper', /id=["']startButton["'][^>]*aria-describedby=["']startHint["']/.test(source));
check('start helper uses human-readable launch copy', /Start focuses controls\. Space also starts\./.test(source));
check('start helper is toggled with existing start button state', /const\s+hint\s*=\s*document\.getElementById\(['"]startHint['"]\)/.test(source) && /hint\.hidden\s*=\s*!visible/.test(source));
check('start helper keeps aria visibility in sync', /hint\.setAttribute\(['"]aria-hidden['"]\s*,\s*visible\s*\?\s*['"]false['"]\s*:\s*['"]true['"]\)/.test(source));
check('mobile start controls have responsive rules', /@media\s*\(max-width:\s*520px\)[\s\S]*#launchPanel[\s\S]*width:\s*min\(340px,\s*calc\(100vw\s*-\s*44px\)\)[\s\S]*#startHint[\s\S]*font-size:\s*14px/.test(source));
check('game start path is preserved', /currentGame\.start\(\)/.test(source) && /this\.start\(\)/.test(source));

const forbiddenTokens = [
  'CLIENTREADY=FALSE',
  'deliveryPerformed=false',
  'clientReady=false',
  'getBackendActor',
  'submitGameScore',
  'spendTokensOnGame',
  'claimRoyalties',
  'endGameSession',
  'Principal.fromText',
  'backendActor',
  'canister',
];
for (const token of forbiddenTokens) {
  check(`does not expose forbidden launch-helper token: ${token}`, !source.includes(token));
}

const failed = checks.filter(c => !c.pass);
for (const c of checks) console.log(`${c.pass ? 'PASS' : 'FAIL'} ${c.name}`);
if (failed.length) {
  console.error(`\nvalidate-swing-blade-start-helper: FAIL (${failed.length}/${checks.length} checks failed)`);
  process.exit(1);
}
console.log(`\nvalidate-swing-blade-start-helper: PASS (${checks.length}/${checks.length} checks passed)`);
