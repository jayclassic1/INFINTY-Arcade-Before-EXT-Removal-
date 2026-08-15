import { readFileSync } from 'node:fs';

const backend = readFileSync(new URL('../backend/main.mo', import.meta.url), 'utf8');
const frontend = readFileSync(new URL('../index.html', import.meta.url), 'utf8');

function assert(condition, message) {
  if (!condition) {
    console.error(`ticket jackpot phase1 static check failed: ${message}`);
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

requireMatch(
  submitGameScore,
  /Result\.Result<\{\s*tickets\s*:\s*Nat;\s*baseTickets\s*:\s*Nat;\s*jackpotTickets\s*:\s*Nat;\s*newRecord\s*:\s*Bool;[\s\S]*jackpotTierLabels\s*:\s*\[Text\];[\s\S]*jackpotUncappedTickets\s*:\s*Nat;[\s\S]*jackpotCapped\s*:\s*Bool;[\s\S]*jackpotPoolRemaining\s*:\s*Nat;[\s\S]*tokenBalance\s*:\s*Nat;[\s\S]*ticketBalance\s*:\s*Nat\s*\},\s*Text>/,
  'submitGameScore ok result must include tickets, baseTickets, jackpotTickets, newRecord, jackpot tier metadata, jackpotPoolRemaining, tokenBalance, ticketBalance'
);

requireMatch(
  backend,
  /transient\s+let\s+JACKPOT_MAX_TICKETS_PER_WIN\s*:\s*Nat\s*=\s*25;/,
  'backend must define JACKPOT_MAX_TICKETS_PER_WIN = 25 near payout constants'
);
requireMatch(
  backend,
  /transient\s+let\s+JACKPOT_POOL_BASIS_POINTS\s*:\s*Nat\s*=\s*1000;/,
  'backend must define JACKPOT_POOL_BASIS_POINTS = 1000'
);

requireMatch(
  submitGameScore,
  /let\s+newRecord\s*=\s*recordValidatedHighScore\(caller,\s*gameId,\s*score\)/,
  'jackpot eligibility must be tied to recordValidatedHighScore result in submitGameScore'
);
requireMatch(
  submitGameScore,
  /let\s+jackpotCalculation\s*=\s*switch\s*\(jackpotConfig\)[\s\S]*if\s*\(config\.enabled\)[\s\S]*calculateTicketJackpotPayout\(config,\s*score,\s*newRecord,\s*remainingBackedAfterBase,\s*remainingDailyAfterBase\)/,
  'jackpot payout must use enabled Phase 2 config/tier calculation'
);
requireMatch(
  submitGameScore,
  /let\s+baseTickets\s*:\s*Nat\s*=\s*ticketPayout;/,
  'normal/base ticket payout must be finalized before jackpot calculation'
);
requireMatch(
  submitGameScore,
  /remainingDailyAfterBase[\s\S]*DAILY_TICKET_CAP\s*-\s*\(dailyEarned\s*\+\s*baseTickets\)/,
  'jackpot must be capped by remaining daily cap after base payout'
);
requireMatch(
  submitGameScore,
  /remainingBackedAfterBase[\s\S]*availableBackedPool\s*-\s*baseTickets/,
  'jackpot must be capped by remaining backed pool after base payout'
);
requireMatch(
  backend,
  /func\s+ticketJackpotTierPayout[\s\S]*remainingBackedAfterBase\s*\*\s*percent\s*\/\s*100[\s\S]*func\s+capTicketJackpotPayout[\s\S]*JACKPOT_MAX_TICKETS_PER_WIN/,
  'jackpot calculation must apply percent-of-backed-pool math and per-win cap'
);
requireMatch(
  submitGameScore,
  /tickets\.put\(caller,\s*tickBal\s*\+\s*totalTicketPayout\)[\s\S]*addDailyTickets\(caller,\s*totalTicketPayout\)[\s\S]*setGameBackedTicketPoolValue\(gameId,\s*availableBackedPool\s*-\s*totalTicketPayout\)/,
  'base + jackpot payout must be awarded atomically and drain the backed pool once'
);

const stableIndex = backend.indexOf('stable var gamePayoutConfigEntries : [(Text, GamePayoutConfig)] = [];');
const jackpotStableIndex = backend.indexOf('stable var ticketJackpotWinEntries : [TicketJackpotWin] = [];');
assert(stableIndex >= 0, 'gamePayoutConfigEntries stable var should exist');
assert(jackpotStableIndex > stableIndex, 'stable jackpot history var must be appended after gamePayoutConfigEntries');
requireMatch(
  backend,
  /type\s+TicketJackpotWin\s*=\s*\{[\s\S]*player\s*:\s*Principal;[\s\S]*gameId\s*:\s*Text;[\s\S]*score\s*:\s*Nat;[\s\S]*jackpotTickets\s*:\s*Nat;[\s\S]*baseTickets\s*:\s*Nat;[\s\S]*timestamp\s*:\s*Int;[\s\S]*\}/,
  'backend must define TicketJackpotWin history record shape'
);
requireMatch(
  backend,
  /if\s*\(jackpotTickets\s*>\s*0\)\s*\{[\s\S]*ticketJackpotWins\.add\(\{[\s\S]*jackpotTickets\s*=\s*jackpotTickets;[\s\S]*baseTickets\s*=\s*baseTickets;[\s\S]*timestamp\s*=\s*now;[\s\S]*\}\)/,
  'backend must append jackpot history only when jackpotTickets > 0'
);
requireMatch(
  backend,
  /public query func getRecentTicketJackpotWins\(limit\s*:\s*Nat\)\s*:\s*async \[TicketJackpotWin\][\s\S]*if\s*\(limit\s*>\s*50\)\s*50\s*else\s*limit/,
  'backend must expose bounded recent jackpot win history query capped at 50'
);
requireMatch(
  backend,
  /public query func getGameTicketJackpotSnapshot\(gameId\s*:\s*Text\)\s*:\s*async \{\s*backedTicketPool\s*:\s*Nat;\s*maxPossibleJackpot\s*:\s*Nat\s*\}/,
  'backend must expose game jackpot snapshot query with backed pool and max possible jackpot'
);

requireMatch(
  frontend,
  /submitGameScore:IDL\.Func\(\[IDL\.Text,IDL\.Nat,IDL\.Nat,IDL\.Text,IDL\.Nat\],\[IDL\.Variant\(\{ok:IDL\.Record\(\{tickets:IDL\.Nat,baseTickets:IDL\.Nat,jackpotTickets:IDL\.Nat,newRecord:IDL\.Bool,jackpotTierLabels:IDL\.Vec\(IDL\.Text\),jackpotUncappedTickets:IDL\.Nat,jackpotCapped:IDL\.Bool,jackpotPoolRemaining:IDL\.Nat,tokenBalance:IDL\.Nat,ticketBalance:IDL\.Nat\}\),err:IDL\.Text\}\)\],\[\]\)/,
  'frontend IDL must include expanded submitGameScore result shape'
);
requireMatch(
  frontend,
  /getRecentTicketJackpotWins:IDL\.Func\(\[IDL\.Nat\],\[IDL\.Vec\(IDL\.Record\(\{player:IDL\.Principal,gameId:IDL\.Text,score:IDL\.Nat,jackpotTickets:IDL\.Nat,baseTickets:IDL\.Nat,timestamp:IDL\.Int\}\)\)\],\['query'\]\)/,
  'frontend IDL must include getRecentTicketJackpotWins query'
);
requireMatch(
  frontend,
  /getGameTicketJackpotSnapshot:IDL\.Func\(\[IDL\.Text\],\[IDL\.Record\(\{backedTicketPool:IDL\.Nat,maxPossibleJackpot:IDL\.Nat\}\)\],\['query'\]\)/,
  'frontend IDL must include getGameTicketJackpotSnapshot query'
);

const endArcadeGameBlock = frontend.match(/async function endArcadeGame\([\s\S]*?\r?\n}\r?\n\r?\nasync function/);
assert(endArcadeGameBlock, 'frontend endArcadeGame block should be discoverable');
const endArcadeGame = endArcadeGameBlock[0];
requireMatch(endArcadeGame, /const\s+baseTickets\s*=\s*Number\(r\.baseTickets\?\?r\.tickets\?\?0\)/, 'endArcadeGame must read baseTickets with compatibility fallback');
requireMatch(endArcadeGame, /const\s+jackpotTickets\s*=\s*Number\(r\.jackpotTickets\?\?0\)/, 'endArcadeGame must read jackpotTickets');
requireMatch(endArcadeGame, /const\s+newRecord\s*=\s*Boolean\(r\.newRecord\)/, 'endArcadeGame must read newRecord from backend');
requireMatch(endArcadeGame, /if\s*\(jackpotTickets\s*>\s*0\)\s*\{[\s\S]*showJackpotPopup\(/, 'endArcadeGame must show jackpot popup only for real backend jackpotTickets');
requireMatch(endArcadeGame, /return\s*\{tickets:totalTickets,totalTickets,baseTickets,jackpotTickets,newRecord,jackpotTierLabels,jackpotUncappedTickets,jackpotCapped\}/, 'endArcadeGame must return compatibility object with tickets plus base/jackpot/newRecord');
assert(!/\bbe\.submitHighScore\(/.test(endArcadeGame), 'endArcadeGame must not call standalone submitHighScore');
assert(!/Math\.random\(\)[\s\S]{0,120}showJackpotPopup|showJackpotPopup[\s\S]{0,120}Math\.random\(\)/.test(endArcadeGame), 'endArcadeGame must not simulate jackpot locally');

console.log('ticket jackpot phase1 static checks passed');
