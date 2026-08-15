import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const mainPath = path.resolve(process.cwd(), 'main.mo');
const source = fs.readFileSync(mainPath, 'utf8');

assert.match(
  source,
  /public shared\(msg\) func spendTokensOnGame\(amount : Nat, gameId : Text\)[\s\S]*if \(amount == 0\) return #err\("Amount must be greater than zero"\);/,
  'spendTokensOnGame should reject zero-amount spends',
);

assert.match(
  source,
  /public shared\(msg\) func submitGameScore\([\s\S]*switch \(gameSubmissions.get\(gameId\)\) \{[\s\S]*case null \{ return #err\("Game not found: " # gameId\) \};/,
  'submitGameScore should fail closed when the game record is missing',
);

assert.match(
  source,
  /public shared\(msg\) func submitGameScore\([\s\S]*if \(tokenCost == 0\) return #err\("Token cost must be greater than zero"\);/,
  'submitGameScore should reject zero-cost submissions',
);

assert.match(
  source,
  /func migrateLegacyGameTicketPoolsIfNeeded\(\)[\s\S]*gameBackedTicketPoolEntries := \[\];/,
  'post-upgrade migration should explicitly clear legacy backed entries after one-way reconciliation',
);

assert.match(
  source,
  /public query func getTicketReserveAudit\(\) : async \{[\s\S]*outstandingBackedLiability : Nat;[\s\S]*coverageGap : Nat;[\s\S]*surplusBacking : Nat;/,
  'reserve audit query should expose backed liability and coverage summary',
);

console.log('model-a-pass3 checks passed');
