import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const mainPath = path.resolve(process.cwd(), 'main.mo');
const source = fs.readFileSync(mainPath, 'utf8');

assert.match(
  source,
  /func computeTicketGamePoolCredit\(amount : Nat\) : Nat \{[\s\S]*amount \* 10;/,
  'ticket-game spend credit should align to the fixed 1 token = 10 backed tickets model',
);

assert.match(
  source,
  /let ticketPoolCredit = computeTicketGamePoolCredit\(amount\);[\s\S]*addToGameRawTicketPool\(gameId, ticketPoolCredit\);[\s\S]*addToGameBackedTicketPool\(gameId, ticketPoolCredit\);/,
  'ticket-game spend path should credit explicit raw and backed ticket pools using one computed amount',
);

assert.match(
  source,
  /let availableBackedPool = getGameBackedTicketPoolValue\(gameId\);[\s\S]*if \(ticketPayout > availableBackedPool\) \{[\s\S]*ticketPayout := availableBackedPool;/,
  'submitGameScore should cap payouts to the game backed pool when requested payout exceeds allocation',
);

assert.match(
  source,
  /setGameBackedTicketPoolValue\(gameId, availableBackedPool - ticketPayout\);/,
  'submitGameScore should decrement the backed pool by the awarded payout',
);

console.log('model-a-pass2 checks passed');
