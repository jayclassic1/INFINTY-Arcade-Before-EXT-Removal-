#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const source = readFileSync(join(process.cwd(), 'index.html'), 'utf8');
const checks = [];
function check(name, pass) {
  checks.push({ name, pass: !!pass });
}

check(
  'defines exact Session already open detector',
  /function\s+isSessionAlreadyOpenError\(e\)\s*{[\s\S]*?getSafeErrorText\(e\)[\s\S]*?normalized\s*===\s*['"]Session already open['"][\s\S]*?}/.test(source)
);
check(
  'insertCoin can mutate replayingExistingSession after backend response',
  /let\s+replayingExistingSession\s*=\s*hasOpenArcadeSession\(id\)/.test(source)
);
check(
  'spendTokensOnGame Session already open resumes instead of alerting',
  /const\s+r\s*=\s*await\s+be\.spendTokensOnGame\(BigInt\(cost\),id\);[\s\S]*?if\(r\.err\)\{[\s\S]*?if\(isSessionAlreadyOpenError\(r\.err\)\)\{[\s\S]*?replayingExistingSession\s*=\s*true;[\s\S]*?resetArcadeSessionState\(id\);[\s\S]*?await\s+syncOnChainTickets\(\);[\s\S]*?}\s*else\s*\{[\s\S]*?alert\(safeGamePaymentErrorMessage\(r\.err\)\);[\s\S]*?return;[\s\S]*?}/.test(source)
);
check(
  'already-open resume does not record a new local spend',
  /if\(!usedFree&&!replayingExistingSession\)\s*trackSpend\(id,cost\);/.test(source)
);
check(
  'successful new session still initializes game state and tracks spend path remains reachable',
  /}\s*else\s*\{[\s\S]*?_gameStartTime\s*=\s*Date\.now\(\);[\s\S]*?_currentGamePlaying\s*=\s*id;[\s\S]*?resetArcadeSessionState\(id\);[\s\S]*?await\s+syncOnChainTickets\(\);[\s\S]*?if\(!usedFree&&!replayingExistingSession\)\s*trackSpend\(id,cost\);/.test(source)
);

const failed = checks.filter(c => !c.pass);
for (const c of checks) console.log(`${c.pass ? 'PASS' : 'FAIL'} ${c.name}`);
if (failed.length) {
  console.error(`\nvalidate-arcade-session-resume: FAIL (${failed.length}/${checks.length} checks failed)`);
  process.exit(1);
}
console.log(`\nvalidate-arcade-session-resume: PASS (${checks.length}/${checks.length} checks passed)`);
