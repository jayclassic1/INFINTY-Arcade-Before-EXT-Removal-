import fs from 'node:fs';

const backend = fs.readFileSync('backend/main.mo', 'utf8');
const frontend = fs.readFileSync('index.html', 'utf8');

function assert(condition, message) {
  if (!condition) {
    console.error(`ticket jackpot phase0 quarantine check failed: ${message}`);
    process.exit(1);
  }
}

assert(
  backend.includes('func recordValidatedHighScore(player : Principal, gameId : Text, score : Nat) : Bool'),
  'backend must define internal recordValidatedHighScore helper'
);

assert(
  /submitGameScore[\s\S]*recordValidatedHighScore\(caller, gameId, score\)/.test(backend),
  'submitGameScore must update leaderboard through validated paid-session path'
);

assert(
  backend.includes('Player high scores must be submitted through submitGameScore'),
  'standalone submitHighScore must reject normal player high-score writes'
);

const submitHighScoreBlock = backend.match(/public shared\(msg\) func submitHighScore[\s\S]*?\r?\n  };\r?\n/);
assert(submitHighScoreBlock, 'submitHighScore function block must be present');
assert(
  /if \(not isAdmin\(caller\)\)/.test(submitHighScoreBlock[0]),
  'submitHighScore must be admin-only/manual compatibility path'
);
assert(
  /#ok\(recordValidatedHighScore\(caller, gameId, score\)\)/.test(submitHighScoreBlock[0]),
  'admin submitHighScore must reuse the same record helper'
);

assert(
  frontend.includes('be.submitGameScore(gameId,BigInt(score),BigInt(gameCost),inputHash,BigInt(durationMs))'),
  'frontend must still submit paid-session scores through submitGameScore'
);

assert(
  !frontend.includes('be.submitHighScore(gameId,BigInt(score))'),
  'frontend must not perform standalone player submitHighScore writes after payout'
);

assert(
  frontend.includes('submitGameScore() after backend paid-session validation'),
  'frontend should document the Phase 0 quarantine at the removed high-score write site'
);

console.log('ticket jackpot phase0 quarantine checks passed');
