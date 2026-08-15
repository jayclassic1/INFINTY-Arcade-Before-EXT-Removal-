import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const backend = fs.readFileSync(path.join(root, 'backend', 'main.mo'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.match(
  backend,
  /func computeTicketGamePoolCredit\(amount : Nat\) : Nat \{[\s\S]*amount \* 10 \* TICKET_GAME_POOL_SHARE\) \/ 100;/,
  'funding should convert gameplay spend through the 70% ticket-pool lane: 7 tickets per token',
);

assert.match(
  backend,
  /public shared\(msg\) func spendTokensOnGame\(amount : Nat, gameId : Text\)[\s\S]*let ticketPoolCredit = computeTicketGamePoolCredit\(amount\);[\s\S]*addToGameRawTicketPool\(gameId, ticketPoolCredit\);[\s\S]*addToGameBackedTicketPool\(gameId, ticketPoolCredit\);/,
  'spendTokensOnGame should flow gameplay funding into raw and backed pools',
);

assert.match(
  backend,
  /let availableBackedPool = getGameBackedTicketPoolValue\(gameId\);[\s\S]*if \(ticketPayout > availableBackedPool\) \{[\s\S]*ticketPayout := availableBackedPool;[\s\S]*let baseTickets : Nat = ticketPayout;[\s\S]*setGameBackedTicketPoolValue\(gameId, availableBackedPool - totalTicketPayout\);/,
  'submitGameScore should cap and drain backed pool payouts including jackpot payouts',
);

assert.match(
  html,
  /Currently backed for payouts: <b style='color:#ffffff'>\$\{backedTicketPoolCount!==null\?`\$\{backedTicketPoolCount\.toLocaleString\(\)\} Tickets`:'Unavailable'\}<\/b>/,
  'public game details should surface the backed pool truthfully',
);

assert.doesNotMatch(
  html,
  /getTreasuryLaneConfig\s*:\s*IDL\.Func|adminFundGameTicketPoolFromDeposit\s*:\s*IDL\.Func|adminConfirmDirectTicketReserveFunding\s*:\s*IDL\.Func|adminAddTicketsToPool\s*:\s*IDL\.Func/,
  'frontend IDL should not advertise unsupported reserve write methods',
);

console.log('model-a-chain checks passed');
