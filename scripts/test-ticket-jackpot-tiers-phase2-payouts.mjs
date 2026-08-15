import fs from 'node:fs';
import assert from 'node:assert/strict';

const backend = fs.readFileSync('backend/main.mo', 'utf8');
const frontend = fs.readFileSync('index.html', 'utf8');
const deployFrontend = fs.readFileSync('.deploy/frontend-public/index.html', 'utf8');

function requireMatch(source, pattern, message) {
  assert.match(source, pattern, message);
}

function requireNotMatch(source, pattern, message) {
  assert.doesNotMatch(source, pattern, message);
}

const submitStart = backend.indexOf('public shared(msg) func submitGameScore');
const submitEnd = backend.indexOf('// ============================================', submitStart);
assert(submitStart >= 0 && submitEnd > submitStart, 'submitGameScore block should be discoverable');
const submitGameScore = backend.slice(submitStart, submitEnd);

requireMatch(
  backend,
  /type\s+TicketJackpotTierPayout\s*=\s*\{[\s\S]*tierLabel\s*:\s*Text;[\s\S]*percent\s*:\s*Nat;[\s\S]*uncappedTickets\s*:\s*Nat;[\s\S]*\}/,
  'backend must model per-tier jackpot payout metadata with source labels and uncapped tickets'
);
requireMatch(
  backend,
  /type\s+TicketJackpotCalculation\s*=\s*\{[\s\S]*tickets\s*:\s*Nat;[\s\S]*uncappedTickets\s*:\s*Nat;[\s\S]*tierLabels\s*:\s*\[Text\];[\s\S]*tierPayouts\s*:\s*\[TicketJackpotTierPayout\];[\s\S]*capped\s*:\s*Bool;[\s\S]*\}/,
  'backend must return combined jackpot calculation metadata'
);
requireMatch(
  backend,
  /func\s+calculateTicketJackpotPayout\(config\s*:\s*GameTicketJackpotConfig,\s*score\s*:\s*Nat,\s*newRecord\s*:\s*Bool,\s*remainingBackedAfterBase\s*:\s*Nat,\s*remainingDailyAfterBase\s*:\s*Nat\)\s*:\s*TicketJackpotCalculation/,
  'jackpot calculation must use config, score, newRecord, remaining backed pool, and remaining daily capacity'
);
requireMatch(
  backend,
  /if\s*\(config\.highPayoutPercent\s*>\s*0\s+and\s+score\s*>=\s*config\.highScoreThreshold\)[\s\S]*labels\.add\("high"\)[\s\S]*else\s+if\s*\(score\s*>=\s*config\.lowScoreThreshold[\s\S]*labels\.add\("low"\)/,
  'high score tier must replace low score tier when both score thresholds match'
);
requireMatch(
  backend,
  /if\s*\(newRecord\s+and\s+config\.newHighScorePayoutPercent\s*>\s*0\)[\s\S]*labels\.add\("new_high_score"\)/,
  'new high score tier must stack independently when newRecord is true and percent is positive'
);
requireMatch(
  backend,
  /func\s+ticketJackpotTierPayout\(tierLabel\s*:\s*Text,[\s\S]*\{[\s\S]*tierLabel\s*=\s*tierLabel;[\s\S]*uncappedTickets\s*=\s*remainingBackedAfterBase\s*\*\s*percent\s*\/\s*100;[\s\S]*\}/,
  'percent math must use the remaining backed ticket pool and preserve the tier source label'
);
requireMatch(
  backend,
  /minNat\(minNat\(remainingBackedAfterBase,\s*remainingDailyAfterBase\),\s*JACKPOT_MAX_TICKETS_PER_WIN\)/,
  'combined payout must be capped by backed pool, remaining daily capacity, and per-play jackpot cap'
);
requireMatch(
  submitGameScore,
  /case\s*\(\?config\)\s*\{\s*if\s*\(config\.enabled\)/,
  'disabled jackpot config must pay zero safely'
);
requireMatch(
  submitGameScore,
  /let\s+jackpotCalculation\s*=\s*switch\s*\(jackpotConfig\)[\s\S]*calculateTicketJackpotPayout\(config,\s*score,\s*newRecord,\s*remainingBackedAfterBase,\s*remainingDailyAfterBase\)/,
  'submitGameScore must calculate deterministic Phase 2 tier payouts from config'
);
requireNotMatch(
  submitGameScore,
  /let\s+jackpotEligible[\s\S]*newRecord[\s\S]*score\s*>=\s*config\.lowScoreThreshold/,
  'submitGameScore must not keep Phase 1 compatibility-only newRecord low-threshold gating'
);
requireMatch(
  submitGameScore,
  /jackpotTierLabels\s*=\s*jackpotCalculation\.tierLabels;[\s\S]*jackpotUncappedTickets\s*=\s*jackpotCalculation\.uncappedTickets;[\s\S]*jackpotCapped\s*=\s*jackpotCalculation\.capped/,
  'submitGameScore response must expose tier labels plus uncapped/capped metadata'
);
requireMatch(
  submitGameScore,
  /ticketJackpotWinDetails\.add\(\{[\s\S]*tierLabels\s*=\s*jackpotCalculation\.tierLabels;[\s\S]*uncappedTickets\s*=\s*jackpotCalculation\.uncappedTickets;[\s\S]*capped\s*=\s*jackpotCalculation\.capped;[\s\S]*\}\)/,
  'jackpot history metadata must include tier/source labels and cap information'
);
requireMatch(
  backend,
  /public\s+query\s+func\s+getRecentTicketJackpotWinDetails\(limit\s*:\s*Nat\)\s*:\s*async\s+\[TicketJackpotWinDetail\]/,
  'backend must expose bounded jackpot win details with source labels'
);

const ticketWinStableIndex = backend.indexOf('stable var ticketJackpotWinEntries : [TicketJackpotWin] = [];');
const legacyConfigStableIndex = backend.indexOf('stable var gameTicketJackpotConfigEntries : [(Text, GameTicketJackpotConfigV1)] = [];');
const v2ConfigStableIndex = backend.indexOf('stable var gameTicketJackpotConfigV2Entries : [(Text, GameTicketJackpotConfig)] = [];');
const tierDetailStableIndex = backend.indexOf('stable var ticketJackpotWinTierEntries : [TicketJackpotWinDetail] = [];');
assert(ticketWinStableIndex >= 0, 'legacy jackpot win stable history must exist');
assert(legacyConfigStableIndex > ticketWinStableIndex, 'legacy jackpot config stable var must preserve its position after win history');
assert(v2ConfigStableIndex > legacyConfigStableIndex, 'v2 jackpot config stable var must preserve its appended position after legacy config');
assert(tierDetailStableIndex > v2ConfigStableIndex, 'new tier detail stable history must be appended after existing jackpot stable vars');

requireMatch(
  frontend,
  /submitGameScore:IDL\.Func\(\[IDL\.Text,IDL\.Nat,IDL\.Nat,IDL\.Text,IDL\.Nat\],\[IDL\.Variant\(\{ok:IDL\.Record\(\{tickets:IDL\.Nat,baseTickets:IDL\.Nat,jackpotTickets:IDL\.Nat,newRecord:IDL\.Bool,jackpotTierLabels:IDL\.Vec\(IDL\.Text\),jackpotUncappedTickets:IDL\.Nat,jackpotCapped:IDL\.Bool,jackpotPoolRemaining:IDL\.Nat,tokenBalance:IDL\.Nat,ticketBalance:IDL\.Nat\}\),err:IDL\.Text\}\)\],\[\]\)/,
  'frontend IDL submitGameScore result must include jackpot tier/source metadata'
);
requireMatch(
  frontend,
  /getRecentTicketJackpotWinDetails:IDL\.Func\(\[IDL\.Nat\],\[IDL\.Vec\(IDL\.Record\(\{player:IDL\.Principal,gameId:IDL\.Text,score:IDL\.Nat,jackpotTickets:IDL\.Nat,baseTickets:IDL\.Nat,tierLabels:IDL\.Vec\(IDL\.Text\),uncappedTickets:IDL\.Nat,capped:IDL\.Bool,timestamp:IDL\.Int\}\)\)\],\['query'\]\)/,
  'frontend IDL must include detailed jackpot history query with source labels'
);
requireNotMatch(frontend, /Phase 1[^\n<]*(does not activate|stacking is inactive|compatibility gate)|does not activate payout stacking yet|compatibility still requires a new validated high score/i, 'frontend must not claim Phase 2 stacking is inactive');
requireMatch(frontend, /High score jackpot replaces the low jackpot[\s\S]*new high score bonus can stack/i, 'frontend copy must explain high replaces low and new-high can stack');
requireMatch(frontend, /const\s+jackpotTierLabels\s*=\s*\(r\.jackpotTierLabels\?\?\[\]\)\.map\(String\)/, 'frontend must read returned jackpot tier/source labels');
requireMatch(frontend, /formatJackpotTierLabels\(jackpotTierLabels\)/, 'frontend must display returned jackpot tier/source labels');

assert.equal(deployFrontend, frontend, '.deploy/frontend-public/index.html must stay byte-for-byte synced with index.html');

console.log('PASS ticket jackpot tiers phase2 payout static checks');
