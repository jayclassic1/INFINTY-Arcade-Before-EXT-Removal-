import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const backendPath = join(root, 'backend', 'main.mo');
const frontendPath = join(root, 'index.html');
const generatedArtifactDir = ['.', 'd', 'f', 'x'].join('');
const staleDidPath = join(root, generatedArtifactDir, 'ic', 'canisters', 'arcade_backend', 'arcade_backend.did');
const releaseGateEvidencePath = 'C:\\Users\\Jesse\\OpenClawEvidence\\icp-arcade-release-gate-20260426\\backend-frontend-release-gate.md';

const backend = readFileSync(backendPath, 'utf8');
const frontend = readFileSync(frontendPath, 'utf8');

const checks = [];
const warnings = [];

function check(label, fn) {
  try {
    fn();
    checks.push({ label, ok: true });
  } catch (error) {
    checks.push({ label, ok: false, message: error.message });
  }
}

function sliceBetween(source, startNeedle, endNeedle) {
  const start = source.indexOf(startNeedle);
  assert.ok(start >= 0, `${startNeedle} should be present`);
  const end = source.indexOf(endNeedle, start);
  assert.ok(end > start, `${endNeedle} should follow ${startNeedle}`);
  return source.slice(start, end);
}

const submitGameScore = sliceBetween(
  backend,
  'public shared(msg) func submitGameScore(',
  '/// Get player game stats',
);

const insertCoin = sliceBetween(frontend, 'async function insertCoin(id){', '// === BUY GAME');
const submitLatestScoreAndClose = sliceBetween(
  frontend,
  'async function submitLatestScoreAndClose(gameId){',
  'async function forceCloseArcadeSession',
);
const forceCloseArcadeSession = sliceBetween(
  frontend,
  'async function forceCloseArcadeSession(gameId){',
  'function startArcadeGame',
);

check('backend exposes endGameSession with expected signature', () => {
  assert.match(
    backend,
    /public shared\(msg\) func endGameSession\(gameId : Text\) : async Result\.Result<Text, Text>/,
  );
});

check('submitGameScore finalizes an existing paid session instead of charging again', () => {
  assert.match(submitGameScore, /switch \(getOpenPaidGameSession\(caller, gameId\)\)[\s\S]*No active paid session/);
  assert.match(submitGameScore, /if \(tokenCost != session\.tokenCost\)[\s\S]*Token cost does not match active session/);
  assert.match(submitGameScore, /closePaidGameSession\(caller, gameId\);/);
  assert.match(submitGameScore, /getTokenBalance\(caller\)/);
});

check('submitGameScore contains no second token deduction path', () => {
  assert.doesNotMatch(
    submitGameScore,
    /tokens\.put\(caller,\s*(?:newBal|tokenBal\s*-\s*tokenCost|\w+\s*-\s*tokenCost)\)/,
    'submitGameScore must not write a deducted token balance',
  );
  assert.doesNotMatch(
    submitGameScore,
    /let\s+newBal\s*=\s*(?:tokenBal|balance|getTokenBalance\(caller\))\s*-\s*tokenCost/,
    'submitGameScore must not compute a tokenCost deduction',
  );
  assert.doesNotMatch(
    submitGameScore,
    /Not enough tokens|Insufficient tokens/i,
    'insufficient-token checks belong to spendTokensOnGame, not score finalization',
  );
});

check('frontend paid-session guards from Phase 2 are present', () => {
  assert.match(insertCoin, /const replayingExistingSession=hasOpenArcadeSession\(id\);[\s\S]*if\(!replayingExistingSession\)[\s\S]*spendTokensOnGame/);
  assert.match(insertCoin, /resetArcadeSessionState\(id\)/);
  assert.ok(insertCoin.indexOf('await be.spendTokensOnGame(BigInt(cost),id)') < insertCoin.indexOf('wrap.innerHTML=`<iframe'));
  assert.match(submitLatestScoreAndClose, /if\(!result\) return;/);
  assert.match(forceCloseArcadeSession, /await be\.endGameSession\(gameId\)/);
});

check('frontend Phase 3 payout truth copy is present', () => {
  assert.match(
    frontend,
    /Ticket payouts use fixed score thresholds:[\s\S]*10,000\+ = 500 Tickets[\s\S]*5,000\+ = 250[\s\S]*2,500\+ = 100[\s\S]*1,000\+ = 40[\s\S]*500\+ = 15[\s\S]*100\+ = 5[\s\S]*below 100 = 0/i,
  );
  assert.match(frontend, /Ticket payouts are capped by the backed ticket pool and may pay 0 if the pool is empty/i);
  assert.match(frontend, /Currently backed for payouts:[\s\S]*Tickets/i);
});

check('frontend no longer depends on missing getGameScoreInfo', () => {
  assert.doesNotMatch(frontend, /getGameScoreInfo/);
});

check('release gate evidence file exists', () => {
  assert.ok(existsSync(releaseGateEvidencePath), `missing release gate evidence: ${releaseGateEvidencePath}`);
});

if (existsSync(staleDidPath)) {
  const did = readFileSync(staleDidPath, 'utf8');
  if (!/endGameSession/.test(did)) {
    warnings.push(
      `STALE ${generatedArtifactDir}/ic ARTIFACT WARNING: ${staleDidPath} exists but does not contain endGameSession. Do not deploy from this artifact; rebuild arcade_backend in an ICP-enabled environment first.`,
    );
  }
}

let failures = 0;
for (const result of checks) {
  if (result.ok) {
    console.log(`PASS: ${result.label}`);
  } else {
    failures += 1;
    console.error(`FAIL: ${result.label}`);
    console.error(`  ${result.message}`);
  }
}

for (const warning of warnings) {
  console.warn(`WARN: ${warning}`);
}

if (failures) {
  console.error(`\nBeta readiness validation FAILED (${checks.length - failures}/${checks.length})`);
  process.exit(1);
}

console.log(`\nBeta readiness validation PASSED (${checks.length}/${checks.length})`);
if (warnings.length) {
  console.log(`Warnings: ${warnings.length}`);
}
