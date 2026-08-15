import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const backendPath = path.join(root, 'backend', 'main.mo');
const frontendPath = path.join(root, 'index.html');
const backend = fs.readFileSync(backendPath, 'utf8');
const frontend = fs.readFileSync(frontendPath, 'utf8');

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

const spendTokensOnGame = sliceBetween(
  backend,
  'public shared(msg) func spendTokensOnGame(amount : Nat, gameId : Text)',
  '/// Win tickets from a game',
);

assert.doesNotMatch(
  submitGameScore,
  /tokens\.put\(caller,\s*(?:tokenBal|\w+)\s*-\s*tokenCost\)/,
  'submitGameScore must not directly deduct tokenCost from caller tokens',
);

assert.match(
  backend,
  /type PaidGameSession = \{[\s\S]*player : Principal;[\s\S]*gameId : Text;[\s\S]*tokenCost : Nat;[\s\S]*openedAt : Int;[\s\S]*open : Bool;[\s\S]*\};/,
  'backend should define explicit paid game session state',
);

assert.match(
  submitGameScore,
  /switch \(getOpenPaidGameSession\(caller, gameId\)\)[\s\S]*No active paid session/,
  'submitGameScore should require an active paid session',
);

assert.match(
  submitGameScore,
  /closePaidGameSession\(caller, gameId\);/,
  'submitGameScore should close/consume the active paid session on successful finalization',
);

const existingSessionCheck = spendTokensOnGame.indexOf('Session already open');
const balanceCheck = spendTokensOnGame.indexOf('let balance = getTokenBalance(caller);');
assert.ok(existingSessionCheck >= 0, 'spendTokensOnGame should reject an existing open session');
assert.ok(balanceCheck >= 0, 'spendTokensOnGame should still check token balance');
assert.ok(existingSessionCheck < balanceCheck, 'spendTokensOnGame should reject an existing open session before balance/deduction');

const openSessionIndex = spendTokensOnGame.indexOf('openPaidGameSession(caller, gameId, amount);');
const deductionIndex = spendTokensOnGame.indexOf('tokens.put(caller, newBal);');
assert.ok(openSessionIndex >= 0, 'spendTokensOnGame should open a paid session');
assert.ok(deductionIndex >= 0, 'spendTokensOnGame should keep its token deduction');
assert.ok(openSessionIndex > deductionIndex, 'spendTokensOnGame should open the session after successful accounting/deduction');

assert.match(
  backend,
  /public shared\(msg\) func endGameSession\(gameId : Text\) : async Result\.Result<Text, Text>/,
  'endGameSession should exist with the required signature',
);

const insertCoin = sliceBetween(frontend, 'async function insertCoin(id){', '// === BUY GAME');
const endArcadeGame = sliceBetween(frontend, 'async function endArcadeGame(gameId,score){', 'async function getGameStats');
const submitLatestScoreAndClose = sliceBetween(frontend, 'async function submitLatestScoreAndClose(gameId){', 'async function forceCloseArcadeSession');
const forceCloseArcadeSession = sliceBetween(frontend, 'async function forceCloseArcadeSession(gameId){', 'function startArcadeGame');

const spendIndex = insertCoin.indexOf('await be.spendTokensOnGame(BigInt(cost),id)');
assert.ok(spendIndex >= 0, 'insertCoin should start a backend paid session with spendTokensOnGame');
const postSpendInsertCoin = insertCoin.slice(spendIndex);
for (const required of [
  '_gameStartTime=Date.now()',
  '_gameInputs=[]',
  '_currentGamePlaying=id',
  'resetArcadeSessionState(id)',
]) {
  assert.ok(postSpendInsertCoin.includes(required), `insertCoin should initialize ${required} after successful backend spend`);
}
const iframeIndex = insertCoin.indexOf("wrap.innerHTML=`<iframe");
assert.ok(iframeIndex > spendIndex, 'insertCoin should not load the iframe before the paid session start succeeds');
assert.match(insertCoin, /const replayingExistingSession=hasOpenArcadeSession\(id\);[\s\S]*if\(!replayingExistingSession\)[\s\S]*spendTokensOnGame/, 'insertCoin should guard backend spend when replaying an existing local session');
assert.doesNotMatch(insertCoin, /startArcadeGame\(id\)/, 'insertCoin should not call startArcadeGame after backend deduction because it performs a local balance gate');

assert.match(endArcadeGame, /if\(result\.err\)\{[\s\S]*safeGamePaymentErrorMessage\(result\.err,[^)]*score submit[^)]*\)[\s\S]*return null;[\s\S]*\}/, 'endArcadeGame should sanitize backend errors and return null on backend err');
assert.doesNotMatch(endArcadeGame, /if\(result\.err\)\{[\s\S]*return \{tickets:0,newRecord:false\};[\s\S]*\}/, 'endArcadeGame backend err must not return a successful-looking result object');
assert.match(endArcadeGame, /catch\(e\)\{[\s\S]*safeGamePaymentErrorMessage\(e,[^)]*score submit[^)]*\)[\s\S]*return null;[\s\S]*\}/, 'endArcadeGame should sanitize thrown errors and return null');

const resultCheckIndex = submitLatestScoreAndClose.indexOf('if(!result) return;');
assert.ok(resultCheckIndex >= 0, 'submitLatestScoreAndClose should stop on failed score finalization');
for (const afterSuccess of ['_arcadeSessionState.scoreSubmitted=true', 'resetArcadeSessionState(\'\')', 'closeArcadeSessionWindowOrModal()', 'renderShowroom()']) {
  const idx = submitLatestScoreAndClose.indexOf(afterSuccess);
  assert.ok(idx > resultCheckIndex, `${afterSuccess} should only happen after confirmed score finalization`);
}

assert.match(frontend, /endGameSession:IDL\.Func\(\[IDL\.Text\],\[IDL\.Variant\(\{ok:IDL\.Text,err:IDL\.Text\}\)\],\[\]\)/, 'frontend IDL should expose endGameSession with the backend signature');
assert.match(frontend, /<button class='btn green' onclick='arcadeButtonHit\(this\);submitLatestScoreAndClose\("\$\{id\}"\)'[^>]*>Submit Score<\/button>/, 'game modal should expose Submit Score in the top-right action row');
assert.match(frontend, /Submit Score<\/button>[\s\S]*Close<\/button>/, 'Submit Score should sit beside the close escape path');
assert.match(frontend, /Finish a run first, then use the top-right Submit Score button\./, 'no-score prompt should point players to the top-right Submit Score button');
assert.doesNotMatch(frontend, /bottom Submit Score button/, 'no-score prompt should not reference the old bottom Submit Score location');
assert.doesNotMatch(frontend, /Leave Game<\/button>/, 'game modal should not expose the old Leave Game button');
assert.doesNotMatch(frontend, />Force Close<\/button>/, 'game modal should label the force-close action as Close');
assert.match(frontend, /id='coinGateButtons'[\s\S]*id='coinPlayBtn'[\s\S]*Balance: <span id='coinGateBalance'/, 'coin gate balance should render below the Play button group');
assert.match(forceCloseArcadeSession, /await be\.endGameSession\(gameId\)/, 'forceCloseArcadeSession should call backend endGameSession');
assert.match(forceCloseArcadeSession, /safeGamePaymentErrorMessage\(result\.err,[^)]*session close[^)]*\)/, 'forceCloseArcadeSession should sanitize backend result errors');
assert.match(forceCloseArcadeSession, /no active paid session[\s\S]*resetArcadeSessionState\(''\)[\s\S]*closeArcadeSessionWindowOrModal\(\)[\s\S]*renderShowroom\(\)/i, 'forceCloseArcadeSession should exit locally when backend reports no active paid session');
assert.match(forceCloseArcadeSession, /catch\(e\)\{[\s\S]*safeGamePaymentErrorMessage\(e,[^)]*session close[^)]*\)[\s\S]*return;[\s\S]*\}/, 'forceCloseArcadeSession should sanitize thrown errors and keep the modal visible');

console.log('paid-session score-flow checks passed');
