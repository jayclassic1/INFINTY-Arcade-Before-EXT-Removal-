import { readFileSync } from 'node:fs';

const backend = readFileSync(new URL('../backend/main.mo', import.meta.url), 'utf8');
const frontend = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const deployFrontend = readFileSync(new URL('../.deploy/frontend-public/index.html', import.meta.url), 'utf8');

function assert(condition, message) {
  if (!condition) {
    console.error(`ticket jackpot admin thresholds static check failed: ${message}`);
    process.exit(1);
  }
}

function requireMatch(source, pattern, message) {
  assert(pattern.test(source), message);
}

const submitStart = backend.indexOf('public shared(msg) func submitGameScore');
const submitEnd = backend.indexOf('  /// Force-close', submitStart);
assert(submitStart >= 0 && submitEnd > submitStart, 'backend submitGameScore block should be discoverable');
const submitGameScore = backend.slice(submitStart, submitEnd);

const jackpotWinStableIndex = backend.indexOf('stable var ticketJackpotWinEntries : [TicketJackpotWin] = [];');
const legacyConfigStableIndex = backend.indexOf('stable var gameTicketJackpotConfigEntries : [(Text, GameTicketJackpotConfigV1)] = [];');
const v2ConfigStableIndex = backend.indexOf('stable var gameTicketJackpotConfigV2Entries : [(Text, GameTicketJackpotConfig)] = [];');
assert(jackpotWinStableIndex >= 0, 'ticketJackpotWinEntries stable var should exist');
assert(legacyConfigStableIndex > jackpotWinStableIndex, 'legacy game ticket jackpot config stable var must stay after jackpot win entries');
assert(v2ConfigStableIndex > legacyConfigStableIndex, 'v2 game ticket jackpot config stable var must be appended after legacy config entries');

requireMatch(
  backend,
  /type\s+GameTicketJackpotConfig\s*=\s*\{[\s\S]*enabled\s*:\s*Bool;[\s\S]*lowScoreThreshold\s*:\s*Nat;[\s\S]*lowPayoutPercent\s*:\s*Nat;[\s\S]*highScoreThreshold\s*:\s*Nat;[\s\S]*highPayoutPercent\s*:\s*Nat;[\s\S]*newHighScorePayoutPercent\s*:\s*Nat;[\s\S]*updatedAt\s*:\s*Int;[\s\S]*\}/,
  'backend must define v2 GameTicketJackpotConfig fields'
);
requireMatch(
  backend,
  /type\s+GameTicketJackpotConfigV1\s*=\s*\{[\s\S]*enabled\s*:\s*Bool;[\s\S]*scoreThreshold\s*:\s*Nat;[\s\S]*updatedAt\s*:\s*Int;[\s\S]*\}/,
  'backend must retain legacy v1 GameTicketJackpotConfigV1'
);
requireMatch(
  backend,
  /type\s+GameTicketJackpotConfigView\s*=\s*\{[\s\S]*gameId\s*:\s*Text;[\s\S]*lowScoreThreshold\s*:\s*Nat;[\s\S]*newHighScorePayoutPercent\s*:\s*Nat;[\s\S]*\}/,
  'backend must define v2 GameTicketJackpotConfigView with gameId and tier fields'
);
requireMatch(
  backend,
  /public\s+shared\(msg\)\s+func\s+setGameTicketJackpotConfig\(gameId\s*:\s*Text,\s*enabled\s*:\s*Bool,\s*lowScoreThreshold\s*:\s*Nat,\s*lowPayoutPercent\s*:\s*Nat,\s*highScoreThreshold\s*:\s*Nat,\s*highPayoutPercent\s*:\s*Nat,\s*newHighScorePayoutPercent\s*:\s*Nat\)\s*:\s*async\s+Result\.Result<GameTicketJackpotConfigView,\s*Text>[\s\S]*not\s+isAdmin\(msg\.caller\)/,
  'admin setter must exist with v2 signature and be admin-only'
);
requireMatch(backend, /setGameTicketJackpotConfig[\s\S]*Text\.size\(gameId\)\s*==\s*0[\s\S]*Game id is required/, 'admin setter must reject blank game ids');
requireMatch(backend, /setGameTicketJackpotConfig[\s\S]*gameSubmissions\.get\(gameId\)[\s\S]*Unknown game/, 'admin setter must require an existing game');
requireMatch(backend, /setGameTicketJackpotConfig[\s\S]*game\.status\s*!=\s*"live"[\s\S]*live\/submitted[\s\S]*not\s+isTicketGameTier\(game\.gameTier\)[\s\S]*ticket-backed/, 'admin setter should require a live/submitted ticket-backed game');
requireMatch(backend, /if\s*\(enabled\s+and\s+lowScoreThreshold\s*==\s*0\)[\s\S]*low score threshold/, 'admin setter must require lowScoreThreshold > 0 when enabled');
requireMatch(backend, /if\s*\(enabled\s+and\s+lowPayoutPercent\s*==\s*0\)[\s\S]*low payout percent/, 'admin setter must require lowPayoutPercent > 0 when enabled');
requireMatch(backend, /highPayoutPercent\s*>\s*0\s+and\s+highScoreThreshold\s*<=\s*lowScoreThreshold/, 'admin setter must validate optional high tier ordering');
requireMatch(backend, /lowPayoutPercent\s*>\s*100\s+or\s+highPayoutPercent\s*>\s*100\s+or\s+newHighScorePayoutPercent\s*>\s*100/, 'admin setter must cap payout percents at 100');
requireMatch(backend, /public\s+query\s+func\s+getGameTicketJackpotConfig\(gameId\s*:\s*Text\)\s*:\s*async\s+\?GameTicketJackpotConfigView/, 'single jackpot config query must exist');
requireMatch(backend, /public\s+query\s+func\s+getAllGameTicketJackpotConfigs\(\)\s*:\s*async\s+\[GameTicketJackpotConfigView\]/, 'all jackpot config query must exist');

requireMatch(submitGameScore, /let\s+newRecord\s*=\s*recordValidatedHighScore\(caller,\s*gameId,\s*score\)/, 'submitGameScore must still validate new high score first');
requireMatch(submitGameScore, /let\s+jackpotConfig\s*=\s*gameTicketJackpotConfigs\.get\(gameId\)/, 'submitGameScore must read per-game jackpot config');
requireMatch(submitGameScore, /let\s+jackpotCalculation\s*=\s*switch\s*\(jackpotConfig\)[\s\S]*if\s*\(config\.enabled\)[\s\S]*calculateTicketJackpotPayout\(config,\s*score,\s*newRecord,\s*remainingBackedAfterBase,\s*remainingDailyAfterBase\)/, 'jackpot payout must be gated by enabled Phase 2 config calculation');
requireMatch(submitGameScore, /let\s+jackpotTickets\s*:\s*Nat\s*=\s*jackpotCalculation\.tickets/, 'jackpotTickets must come from capped Phase 2 calculation');

requireMatch(frontend, /const\s+GameTicketJackpotConfigView\s*=\s*IDL\.Record\(\{gameId:IDL\.Text,enabled:IDL\.Bool,lowScoreThreshold:IDL\.Nat,lowPayoutPercent:IDL\.Nat,highScoreThreshold:IDL\.Nat,highPayoutPercent:IDL\.Nat,newHighScorePayoutPercent:IDL\.Nat,updatedAt:IDL\.Int\}\)/, 'frontend IDL must declare v2 GameTicketJackpotConfigView');
requireMatch(frontend, /setGameTicketJackpotConfig:IDL\.Func\(\[IDL\.Text,IDL\.Bool,IDL\.Nat,IDL\.Nat,IDL\.Nat,IDL\.Nat,IDL\.Nat\],\[IDL\.Variant\(\{ok:GameTicketJackpotConfigView,err:IDL\.Text\}\)\],\[\]\)/, 'frontend IDL must include v2 setGameTicketJackpotConfig');
requireMatch(frontend, /getGameTicketJackpotConfig:IDL\.Func\(\[IDL\.Text\],\[IDL\.Opt\(GameTicketJackpotConfigView\)\],\['query'\]\)/, 'frontend IDL must include getGameTicketJackpotConfig');
requireMatch(frontend, /getAllGameTicketJackpotConfigs:IDL\.Func\(\[\],\[IDL\.Vec\(GameTicketJackpotConfigView\)\],\['query'\]\)/, 'frontend IDL must include getAllGameTicketJackpotConfigs');
requireMatch(frontend, /Ticket Jackpot Tiers[\s\S]*jackpotlowScoreThreshold_[\s\S]*jackpotlowPayoutPercent_[\s\S]*jackpothighScoreThreshold_[\s\S]*jackpothighPayoutPercent_[\s\S]*jackpotnewHighScorePayoutPercent_[\s\S]*saveGameTicketJackpotConfig/, 'frontend admin UI must include v2 jackpot tier controls and save method');
requireMatch(frontend, /High score jackpot replaces the low jackpot[\s\S]*new high score bonus can stack/i, 'player/admin copy must explain Phase 2 stacking semantics');

assert(frontend === deployFrontend, '.deploy/frontend-public/index.html must match index.html byte-for-byte');

console.log('ticket jackpot admin thresholds static checks passed');
