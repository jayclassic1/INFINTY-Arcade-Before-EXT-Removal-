#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const backend = readFileSync(join(root, 'backend', 'main.mo'), 'utf8');
const frontend = readFileSync(join(root, 'index.html'), 'utf8');

const checks = [];
function check(name, fn) {
  checks.push([name, fn]);
}

function has(source, pattern) {
  return pattern.test(source);
}

check('backend exposes authoritative ticket/non-ticket split constants', () => {
  assert.match(backend, /TICKET_GAME_CREATOR_SHARE\s*:\s*Nat\s*=\s*20\b/);
  assert.match(backend, /TICKET_GAME_DAO_SHARE\s*:\s*Nat\s*=\s*5\b/);
  assert.match(backend, /TICKET_GAME_BURN_SHARE\s*:\s*Nat\s*=\s*5\b/);
  assert.match(backend, /TICKET_GAME_POOL_SHARE\s*:\s*Nat\s*=\s*70\b/);
  assert.match(backend, /REGULAR_GAME_CREATOR_SHARE\s*:\s*Nat\s*=\s*80\b/);
  assert.match(backend, /REGULAR_GAME_DAO_SHARE\s*:\s*Nat\s*=\s*10\b/);
  assert.match(backend, /REGULAR_GAME_BURN_SHARE\s*:\s*Nat\s*=\s*10\b/);
  assert.match(backend, /NFT_CREATOR_SHARE\s*:\s*Nat\s*=\s*90\b/);
});

check('backend spendTokensOnGame credits ticket games at 20% and regular games at 80%', () => {
  assert.match(backend, /let\s+isTicketGame\s*=\s+isTicketGameSubmission\(game\)/);
  assert.match(backend, /let\s+creatorShare\s*=\s*if\s*\(isTicketGame\)\s*TICKET_GAME_CREATOR_SHARE\s*else\s*REGULAR_GAME_CREATOR_SHARE/);
  assert.match(backend, /let\s+creatorShareE8s\s*:\s*Nat\s*=\s*\(icpValueE8s\s*\*\s*creatorShare\)\s*\/\s*100/);
});

check('backend ticket-pool credit uses the 70% ticket-game pool share', () => {
  assert.match(backend, /func\s+computeTicketGamePoolCredit\(amount\s*:\s*Nat\)\s*:\s*Nat\s*{[\s\S]*\(amount\s*\*\s*10\s*\*\s*TICKET_GAME_POOL_SHARE\)\s*\/\s*100[\s\S]*}/);
});

check('getRevenueSplits returns all authoritative game split fields', () => {
  assert.match(backend, /ticketGameCreatorShare\s*:\s*Nat/);
  assert.match(backend, /ticketGameDaoShare\s*:\s*Nat/);
  assert.match(backend, /ticketGameBurnShare\s*:\s*Nat/);
  assert.match(backend, /ticketGamePoolShare\s*:\s*Nat/);
  assert.match(backend, /regularGameCreatorShare\s*:\s*Nat/);
  assert.match(backend, /regularGameDaoShare\s*:\s*Nat/);
  assert.match(backend, /regularGameBurnShare\s*:\s*Nat/);
});

check('frontend copy states 20/5/5/70 ticket and 80/10/10 regular splits', () => {
  assert.ok(has(frontend, /Ticket games:\s*<b[^>]*>20%<\/b>[^\n]{0,180}70%[^\n]{0,80}ticket pool[^\n]{0,80}5% DAO[^\n]{0,80}5% burned/i));
  assert.ok(has(frontend, /(?:Regular|Non-ticket) games:\s*<b[^>]*>80%<\/b>[^\n]{0,160}10% DAO[^\n]{0,80}10% burned/i));
  assert.ok(has(frontend, /Ticket games send 70% into that game\'s Ticket pool, 20% to the game developer as ICP royalties, 5% to the DAO in Tokens, and 5% is burned/i));
  assert.ok(has(frontend, /Non-ticket games send 80% to the game developer as ICP royalties, 10% to the DAO in Tokens, and 10% is burned/i));
});

check('frontend preserves closed-loop tickets and ICP e8s claimable earnings language', () => {
  assert.match(frontend, /Tickets are prize\/perk points only/);
  assert.match(frontend, /Tickets cannot be exchanged for ICP/);
  assert.match(frontend, /Creator\/seller ICP e8s claimable earnings/);
  assert.match(frontend, /ICP e8s claimable earnings/);
});

const failures = [];
for (const [name, fn] of checks) {
  try {
    fn();
  } catch (error) {
    failures.push(`${name}: ${error.message}`);
  }
}

if (failures.length > 0) {
  console.error(`Economy split validation FAILED (${checks.length - failures.length}/${checks.length})`);
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`Economy split validation PASSED (${checks.length}/${checks.length})`);
for (const [name] of checks) console.log(`PASS ${name}`);
