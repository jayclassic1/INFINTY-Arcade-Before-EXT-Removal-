import fs from 'node:fs';
import assert from 'node:assert/strict';

const frontend = fs.readFileSync('index.html', 'utf8');
const deployFrontend = fs.readFileSync('.deploy/frontend-public/index.html', 'utf8');

function requireMatch(body, regex, message) {
  assert.match(body, regex, message);
}

requireMatch(
  frontend,
  /getRecentTicketJackpotWinDetails:IDL\.Func\(\[IDL\.Nat\],\[IDL\.Vec\(IDL\.Record\(\{player:IDL\.Principal,gameId:IDL\.Text,score:IDL\.Nat,jackpotTickets:IDL\.Nat,baseTickets:IDL\.Nat,tierLabels:IDL\.Vec\(IDL\.Text\),uncappedTickets:IDL\.Nat,capped:IDL\.Bool,timestamp:IDL\.Int\}\)\)\],\['query'\]\)/,
  'frontend IDL must expose getRecentTicketJackpotWinDetails with tier/cap metadata'
);

requireMatch(
  frontend,
  /async\s+function\s+loadRecentTicketJackpotHistory\(be,\s*limit\s*=\s*10\)[\s\S]*getRecentTicketJackpotWinDetails\(BigInt\(limit\)\)[\s\S]*catch[\s\S]*getRecentTicketJackpotWins\(BigInt\(limit\)\)/,
  'history loader must prefer detailed jackpot history and fall back to legacy wins'
);

requireMatch(
  frontend,
  /function\s+formatTicketJackpotHistoryRow\([\s\S]*formatJackpotTierLabels\(win\.tierLabels\|\|\[\]\)[\s\S]*uncappedTickets[\s\S]*capped/i,
  'history rows must format tier labels and capped/uncapped metadata'
);

requireMatch(
  frontend,
  /function\s+formatTicketJackpotPopupContent\(jackpotTierLabels,totalTickets\)[\s\S]*Mini Jackpot![\s\S]*NEW HIGH SCORE JACKPOT[\s\S]*Larger Jackpot![\s\S]*'You won '\+Number\(totalTickets\|\|0\)\.toLocaleString\(\)\+' Tickets'[\s\S]*Click anywhere to continue/,
  'player popup must label mini/larger/new-high jackpot wins and show total tickets paid including ladder payout'
);

requireMatch(
  frontend,
  /showJackpotPopup\(formatTicketJackpotPopupContent\(jackpotTierLabels,totalTickets\),'ticket'\)/,
  'score submit must show the ticket jackpot popup with total backend-paid tickets'
);

requireMatch(
  frontend,
  /low score jackpot is score-threshold based[\s\S]*high score jackpot replaces the low jackpot[\s\S]*new high score bonus can stack[\s\S]*validated new record[\s\S]*backend capped by pool, daily, and per-play safety/i,
  'player-facing copy must clearly state low threshold, high replaces low, validated new-high stacking, and backend caps'
);

requireMatch(
  frontend,
  /Current configured percentages:[\s\S]*Low \$\{Number\(lowPayoutPercent\|\|0\)\}%[\s\S]*High \$\{Number\(highPayoutPercent\|\|0\)\}%[\s\S]*New high score \$\{Number\(newHighScorePayoutPercent\|\|0\)\}%[\s\S]*Stacking preview:/,
  'admin preview must show configured percentages and plain-English stacking summary'
);

requireMatch(
  frontend,
  /Per winner:[\s\S]{0,160}&middot;[\s\S]{0,80}winner/,
  'admin lottery history row must use a readable separator before winner count'
);

assert.doesNotMatch(
  frontend,
  /Per winner:[\s\S]{0,160}\?\s*\$\{\(winners\|\|\[\]\)\.length\}/,
  'admin lottery history row must not render a literal question-mark separator before winner count'
);

assert.equal(deployFrontend, frontend, '.deploy/frontend-public/index.html must be byte-for-byte synced with index.html');

console.log('PASS ticket jackpot tiers phase3 frontend/history static checks');
