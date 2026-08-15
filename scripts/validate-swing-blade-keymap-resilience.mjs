#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const source = readFileSync(join(process.cwd(), 'index.html'), 'utf8');
const checks = [];
function check(name, pass) { checks.push({ name, pass: !!pass }); }

check(
  'getKeyMap catches malformed localStorage JSON',
  /try\{\s*saved=JSON\.parse\(localStorage\.getItem\(['"]arcade_keymap['"]\)\|\|['"]null['"]\);\s*}\s*catch\(_e\)\{\s*saved=null;\s*}/.test(source)
);
check(
  'getKeyMap always returns p1 and p2 maps based on defaults',
  /const\s+normalized=\{p1:\{\.\.\.defaults\.p1\},p2:\{\.\.\.defaults\.p2\}\}/.test(source) && /return\s+normalized;/.test(source)
);
check(
  'getKeyMap only accepts non-empty string saved key codes',
  /if\(typeof\s+code===['"]string['"]&&code\.trim\(\)\)\s*normalized\[player\]\[action\]=code;/.test(source)
);
check(
  'forwarder tolerates missing player map',
  /const\s+playerMap=km\[player\]\|\|\{\};/.test(source)
);
check(
  'Space fallback sends unless exact P1-A was already sent',
  /let\s+nativeFallbackAlreadySent\s*=\s*false/.test(source) && /if\(fallback&&player===fallback\.player&&action===fallback\.action\)\s*nativeFallbackAlreadySent=true/.test(source) && /if\(fallback&&!nativeFallbackAlreadySent\)\{[\s\S]*?postOrQueueArcadeKeyToGame\(iframe,\{type:['"]arcade-key['"],\.\.\.fallback,state,source:['"]native-fallback['"]\}\)/.test(source)
);
check(
  'Space remains mapped as P1-A native fallback',
  /ARCADE_NATIVE_KEY_FALLBACKS\s*=\s*\{\s*Space\s*:\s*\{\s*player\s*:\s*['"]p1['"]\s*,\s*action\s*:\s*['"]a['"]\s*}\s*}/.test(source)
);

const failed = checks.filter(c => !c.pass);
for (const c of checks) console.log(`${c.pass ? 'PASS' : 'FAIL'} ${c.name}`);
if (failed.length) {
  console.error(`\nvalidate-swing-blade-keymap-resilience: FAIL (${failed.length}/${checks.length} checks failed)`);
  process.exit(1);
}
console.log(`\nvalidate-swing-blade-keymap-resilience: PASS (${checks.length}/${checks.length} checks passed)`);
