import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const backend = readFileSync(resolve(root, 'backend/main.mo'), 'utf8');
const frontend = readFileSync(resolve(root, 'index.html'), 'utf8');
const deployFrontend = readFileSync(resolve(root, '.deploy/frontend-public/index.html'), 'utf8');

function assertPattern(source, pattern, message) {
  if (!pattern.test(source)) {
    throw new Error(message);
  }
}

function assertNotPattern(source, pattern, message) {
  if (pattern.test(source)) {
    throw new Error(message);
  }
}

assertPattern(
  backend,
  /type\s+GamePayoutConfig\s*=\s*\{[\s\S]*enabled\s*:\s*Bool[\s\S]*thresholds\s*:\s*\[Nat\][\s\S]*\}/,
  'backend should define a GamePayoutConfig with enabled flag and Nat threshold list',
);

assertPattern(
  backend,
  /stable\s+var\s+gamePayoutConfigEntries\s*:\s*\[\(Text,\s*GamePayoutConfig\)\]/,
  'backend should persist per-game payout configs in stable storage',
);

assertPattern(
  backend,
  /public\s+shared\(msg\)\s+func\s+setGamePayoutConfig[\s\S]*thresholds\.size\(\)\s*!=\s*7[\s\S]*validatePayoutThresholds[\s\S]*gamePayoutConfigs\.put/,
  'backend should expose admin-only setGamePayoutConfig that requires exactly 7 validated thresholds',
);

assertPattern(
  backend,
  /public\s+query\s+func\s+getGamePayoutConfig\s*\(gameId\s*:\s*Text\)/,
  'backend should expose getGamePayoutConfig query',
);

assertPattern(
  backend,
  /func\s+calculateConfiguredTicketPayout[\s\S]*while\s*\([\s\S]*thresholds\.size\(\)[\s\S]*level\s*:=\s*i[\s\S]*if\s*\(level\s*>\s*6\)/,
  'backend should calculate 0..6 ticket payout from the highest configured threshold <= score',
);

assertNotPattern(
  backend,
  /if\s*\(totalPlays\s*<\s*TRIAL_PLAYS\)\s*\{[\s\S]*tickets\s*=\s*0[\s\S]*\};[\s\S]*\/\/ CHECK 5: Calculate tickets from score/,
  'submitGameScore should not silently apply the old first-5-play no-ticket gate before payout calculation',
);

assertPattern(
  backend,
  /transient\s+let\s+MAX_TICKETS_PER_ROUND\s*:\s*Nat\s*=\s*6\s*;/,
  'normal ticket payout cap should be 6 tickets for v1',
);

assertPattern(
  backend,
  /public\s+shared\(msg\)\s+func\s+setGamePayoutConfig[\s\S]*not\s+isAdmin\(msg\.caller\)/,
  'backend setGamePayoutConfig should use existing admin authorization',
);

assertPattern(
  frontend,
  /payout-config|Payout Ladder|saveGamePayoutConfig|renderPayoutLadder|loadPayoutConfig/,
  'frontend should include payout ladder/status/admin controls',
);

assertPattern(
  deployFrontend,
  /payout-config|Payout Ladder|saveGamePayoutConfig|renderPayoutLadder|loadPayoutConfig/,
  'deploy frontend copy should include payout ladder/status/admin controls',
);

for (const [label, source] of [['frontend', frontend], ['deploy frontend', deployFrontend]]) {
  assertNotPattern(
    source,
    /First 5 plays|5 trial plays|trial\/no-ticket-payout|500 tickets\/round|10,000\+ = 500|PAYOUT_TABLE|estTickets/,
    `${label} should not retain stale Phase 0/old high-payout ticket copy or local payout estimates`,
  );
}

if (frontend !== deployFrontend) {
  throw new Error('index.html and .deploy/frontend-public/index.html should remain synchronized');
}

console.log('ticket payout config static checks passed');
