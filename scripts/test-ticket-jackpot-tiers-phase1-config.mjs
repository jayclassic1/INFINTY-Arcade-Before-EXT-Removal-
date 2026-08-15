import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const backend = readFileSync(join(root, 'backend', 'main.mo'), 'utf8');
const frontend = readFileSync(join(root, 'index.html'), 'utf8');
const deployFrontend = readFileSync(join(root, '.deploy', 'frontend-public', 'index.html'), 'utf8');

const v2Fields = [
  'enabled',
  'lowScoreThreshold',
  'lowPayoutPercent',
  'highScoreThreshold',
  'highPayoutPercent',
  'newHighScorePayoutPercent',
  'updatedAt',
];

function assertRecordFields(source, typeName, fields, extra = []) {
  const match = source.match(new RegExp(`type\\s+${typeName}\\s*=\\s*\\{([\\s\\S]*?)\\n\\s*\\};`));
  assert(match, `${typeName} must be defined`);
  const body = match[1];
  for (const field of [...extra, ...fields]) {
    assert(new RegExp(`${field}\\s*:`).test(body), `${typeName} must include ${field}`);
  }
}

assertRecordFields(backend, 'GameTicketJackpotConfig', v2Fields);
assertRecordFields(backend, 'GameTicketJackpotConfigView', v2Fields, ['gameId']);
assertRecordFields(backend, 'GameTicketJackpotConfigV1', ['enabled', 'scoreThreshold', 'updatedAt']);

const stableOrder = [
  'stable var ticketJackpotWinEntries : [TicketJackpotWin] = [];',
  'stable var gameTicketJackpotConfigEntries : [(Text, GameTicketJackpotConfigV1)] = [];',
  'stable var gameTicketJackpotConfigV2Entries : [(Text, GameTicketJackpotConfig)] = [];',
];
let lastIndex = -1;
for (const needle of stableOrder) {
  const index = backend.indexOf(needle);
  assert(index > lastIndex, `stable field order must retain/appends ${needle}`);
  lastIndex = index;
}

assert.match(
  backend,
  /func\s+normalizeGameTicketJackpotConfig\(legacy\s*:\s*GameTicketJackpotConfigV1\)\s*:\s*GameTicketJackpotConfig[\s\S]*lowScoreThreshold\s*=\s*legacy\.scoreThreshold[\s\S]*lowPayoutPercent\s*=\s*JACKPOT_POOL_PERCENT[\s\S]*highScoreThreshold\s*=\s*0[\s\S]*highPayoutPercent\s*=\s*0[\s\S]*newHighScorePayoutPercent\s*=\s*JACKPOT_POOL_PERCENT/,
  'backend must normalize v1 single-threshold configs into v2 tier config defaults'
);

assert.match(
  backend,
  /public\s+shared\(msg\)\s+func\s+setGameTicketJackpotConfig\(gameId\s*:\s*Text,\s*enabled\s*:\s*Bool,\s*lowScoreThreshold\s*:\s*Nat,\s*lowPayoutPercent\s*:\s*Nat,\s*highScoreThreshold\s*:\s*Nat,\s*highPayoutPercent\s*:\s*Nat,\s*newHighScorePayoutPercent\s*:\s*Nat\)\s*:\s*async\s+Result\.Result<GameTicketJackpotConfigView,\s*Text>[\s\S]*not\s+isAdmin\(msg\.caller\)/,
  'admin setter must accept all v2 phase-1 fields and remain admin-only'
);

for (const validation of [
  /Text\.size\(gameId\)\s*==\s*0[\s\S]*Game id is required/,
  /gameSubmissions\.get\(gameId\)[\s\S]*Unknown game/,
  /game\.status\s*!=\s*"live"[\s\S]*live\/submitted[\s\S]*not\s+isTicketGameTier\(game\.gameTier\)[\s\S]*ticket-backed/,
  /enabled\s+and\s+lowScoreThreshold\s*==\s*0[\s\S]*low score threshold/,
  /enabled\s+and\s+lowPayoutPercent\s*==\s*0[\s\S]*low payout/,
  /highPayoutPercent\s*>\s*0\s+and\s+highScoreThreshold\s*<=\s*lowScoreThreshold[\s\S]*high score threshold/,
  /lowPayoutPercent\s*>\s*100\s+or\s+highPayoutPercent\s*>\s*100\s+or\s+newHighScorePayoutPercent\s*>\s*100[\s\S]*0\.\.100/,
]) {
  assert.match(backend, validation, `backend validation missing: ${validation}`);
}

assert.match(backend, /public\s+query\s+func\s+getGameTicketJackpotConfig\(gameId\s*:\s*Text\)\s*:\s*async\s+\?GameTicketJackpotConfigView/, 'single config query must return v2 view');
assert.match(backend, /public\s+query\s+func\s+getAllGameTicketJackpotConfigs\(\)\s*:\s*async\s+\[GameTicketJackpotConfigView\]/, 'all configs query must return v2 views');

const submitStart = backend.indexOf('public shared(msg) func submitGameScore');
const submitEnd = backend.indexOf('  /// Force-close', submitStart);
assert(submitStart >= 0 && submitEnd > submitStart, 'submitGameScore block should be discoverable');
const submitGameScore = backend.slice(submitStart, submitEnd);
assert.match(submitGameScore, /let\s+jackpotCalculation\s*=\s*switch\s*\(jackpotConfig\)[\s\S]*calculateTicketJackpotPayout\(config,\s*score,\s*newRecord,\s*remainingBackedAfterBase,\s*remainingDailyAfterBase\)/, 'Phase 2 jackpot calculation must use config, score, newRecord, and cap inputs');
assert.match(backend, /highPayoutPercent[\s\S]*newHighScorePayoutPercent/, 'Phase 2 submitGameScore must support high-tier and new-high payout stacking');

assert.match(frontend, /const\s+GameTicketJackpotConfigView\s*=\s*IDL\.Record\(\{gameId:IDL\.Text,enabled:IDL\.Bool,lowScoreThreshold:IDL\.Nat,lowPayoutPercent:IDL\.Nat,highScoreThreshold:IDL\.Nat,highPayoutPercent:IDL\.Nat,newHighScorePayoutPercent:IDL\.Nat,updatedAt:IDL\.Int\}\)/, 'frontend IDL must declare v2 config view');
assert.match(frontend, /setGameTicketJackpotConfig:IDL\.Func\(\[IDL\.Text,IDL\.Bool,IDL\.Nat,IDL\.Nat,IDL\.Nat,IDL\.Nat,IDL\.Nat\]/, 'frontend setter IDL must accept v2 fields');
assert.match(frontend, /Ticket Jackpot Tiers/, 'admin UI must label the tier config');
for (const id of ['lowScoreThreshold', 'lowPayoutPercent', 'highScoreThreshold', 'highPayoutPercent', 'newHighScorePayoutPercent']) {
  assert(frontend.includes(`jackpot${id}_`), `admin UI must expose ${id}`);
}
assert.match(frontend, /High score jackpot replaces the low jackpot[\s\S]*new high score bonus can stack/i, 'frontend copy must explain Phase 2 stacking semantics');

assert.equal(frontend, deployFrontend, '.deploy/frontend-public/index.html must remain byte-for-byte synced with index.html');

console.log('PASS ticket jackpot tiers phase1 config static checks');
