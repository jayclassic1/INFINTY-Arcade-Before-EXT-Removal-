const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

const checks = [
  ['IDL exposes getGameBackedTicketPool', /getGameBackedTicketPool\s*:\s*IDL\.Func/],
  ['IDL exposes getGameRawTicketPool', /getGameRawTicketPool\s*:\s*IDL\.Func/],
  ['Public game details use backed pool helper', /openGameDetails[\s\S]*getGameBackedTicketPoolForDisplay/],
  ['Public game details render numeric backed pool copy', /Backed Ticket Pool[\s\S]*Currently backed for payouts[\s\S]*toLocaleString\(\)\} Tickets/],
  ['Admin list shows raw and backed pools separately', /renderGameAdminList[\s\S]*(Raw Pool[\s\S]*Backed Pool|Backed Pool[\s\S]*Raw Pool)/],
  ['Ticket reserve UI does not expose unsupported reserve write methods', html => !/getTreasuryLaneConfig\s*:\s*IDL\.Func|adminFundGameTicketPoolFromDeposit\s*:\s*IDL\.Func|adminConfirmDirectTicketReserveFunding\s*:\s*IDL\.Func|adminAddTicketsToPool\s*:\s*IDL\.Func/.test(html)],
  ['Ticket funding preview catch uses safe generic copy', /renderTicketFundingPreview[\s\S]*Ticket funding preview is temporarily unavailable[\s\S]*console\.warn\('Ticket funding preview failed:',safeGamePaymentErrorMessage\(e\)\)/],
  ['Ticket payout copy uses threshold source-of-truth', /Score (?:>=|&gt;=) 10,000[\s\S]*500 Tickets[\s\S]*Score (?:>=|&gt;=) 5,000[\s\S]*250 Tickets[\s\S]*Score (?:>=|&gt;=) 2,500[\s\S]*100 Tickets[\s\S]*Score (?:>=|&gt;=) 1,000[\s\S]*40 Tickets[\s\S]*Score (?:>=|&gt;=) 500[\s\S]*15 Tickets[\s\S]*Score (?:>=|&gt;=) 100[\s\S]*5 Tickets[\s\S]*Below 100[\s\S]*0 Tickets/i],
  ['Player-facing ticket UI states backed pool payout cap', /ticket payouts are capped by the backed ticket pool and may pay 0 if the pool is empty/i],
  ['Player-facing ticket UI has no active percentile payout promise', html => !/last 100 scores[\s\S]{0,160}percentile model|percentile-based payouts|percentile model ranks scores/i.test(html)],
  ['Player-facing ticket UI has no active ticking jackpot promise', html => !/Ticking Jackpot|scales up to\s*<b[^>]*>80%|monster JACKPOTS/i.test(html)],
  ['Frontend does not depend on missing getGameScoreInfo query', html => !/getGameScoreInfo/.test(html)],
];

let failed = 0;
for (const [label, pattern] of checks) {
  const ok = pattern instanceof RegExp ? pattern.test(html) : pattern(html);
  if (!ok) {
    console.error(`FAIL: ${label}`);
    failed++;
  } else {
    console.log(`PASS: ${label}`);
  }
}

if (failed) process.exit(1);
console.log('All ticket pool frontend checks passed.');
