#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const backend = readFileSync(join(root, 'backend', 'main.mo'), 'utf8');
const frontend = readFileSync(join(root, 'index.html'), 'utf8');

const checks = [];
function check(label, fn) {
  checks.push([label, fn]);
}

function requireMatch(source, pattern, label) {
  assert.match(source, pattern, label);
}

function sliceBetween(source, startNeedle, endNeedle, label = startNeedle) {
  const start = source.indexOf(startNeedle);
  assert.notEqual(start, -1, `missing start for ${label}`);
  const end = source.indexOf(endNeedle, start);
  assert.ok(end > start, `missing end for ${label}`);
  return source.slice(start, end);
}

function extractFunction(source, name) {
  const candidates = [
    `public shared(msg) func ${name}(`,
    `public shared(_msg) func ${name}(`,
    `public shared func ${name}(`,
    `public query func ${name}(`,
    `func ${name}(`,
    `async function ${name}(`,
    `function ${name}(`,
  ];
  let start = -1;
  for (const candidate of candidates) {
    start = source.indexOf(candidate);
    if (start !== -1) break;
  }
  assert.notEqual(start, -1, `missing function ${name}`);
  const brace = source.indexOf('{', start);
  assert.notEqual(brace, -1, `missing opening brace for ${name}`);
  let depth = 0;
  for (let i = brace; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  throw new Error(`unterminated function ${name}`);
}

const convertDepositToTokens = extractFunction(backend, 'convertDepositToTokens');
const spendTokensOnGame = extractFunction(backend, 'spendTokensOnGame');
const claimRoyalties = extractFunction(backend, 'claimRoyalties');
const getRevenueSplits = extractFunction(backend, 'getRevenueSplits');
const getEconomyRates = extractFunction(backend, 'getEconomyRates');
const frontendServiceBlock = frontend;

check('canonical canister targets are documented in CANONICAL.md only, not inferred from legacy roots', () => {
  const canonical = readFileSync(join(root, 'CANONICAL.md'), 'utf8');
  assert.match(canonical, /canonicalSource:[\s\S]*infinity-arcade-Jay/i);
  assert.match(canonical, /mprew-viaaa-aaaah-quola-cai/);
  assert.match(canonical, /pifyq-raaaa-aaaab-agrqq-cai/);
  assert.match(canonical, /Legacy[\s\S]*reference-only/i);
});

check('ICP deposit conversion uses caller subaccount balance and updates credit balances only after ledger transfer succeeds', () => {
  requireMatch(convertDepositToTokens, /if \(Principal\.isAnonymous\(caller\)\) return #err\("Must be authenticated"\)/, 'deposit conversion must reject anonymous callers');
  requireMatch(convertDepositToTokens, /amountE8s < 1_000_000/, 'deposit conversion must reject deposits below 0.01 ICP');
  requireMatch(convertDepositToTokens, /icrc1_balance_of\(\{ owner = selfPrincipal; subaccount = \?fromSub \}\)/, 'deposit conversion must inspect the caller deposit subaccount');
  requireMatch(convertDepositToTokens, /await ICP_LEDGER\.icrc1_transfer/, 'deposit conversion must move ICP before crediting tokens');
  const transferIndex = convertDepositToTokens.indexOf('await ICP_LEDGER.icrc1_transfer');
  const creditIndex = convertDepositToTokens.indexOf('tokens.put(caller, newBal)');
  assert.ok(creditIndex > transferIndex, 'token credit must occur after successful ledger transfer');
});

check('duplicate deposit prevention is present but scoped to completed ledger transfer block indexes', () => {
  requireMatch(backend, /stable var claimedDeposits\s*:\s*\[Nat\]\s*=\s*\[\]/, 'stable claimed deposit indexes must exist');
  requireMatch(backend, /transient var claimedSet\s*=\s*HashMap\.HashMap<Nat, Bool>/, 'runtime claimed deposit set must exist');
  requireMatch(convertDepositToTokens, /case \(#Ok\(blockIndex\)\)/, 'deposit conversion must inspect transfer block index');
  requireMatch(convertDepositToTokens, /if \(Option\.isSome\(claimedSet\.get\(blockIndex\)\)\)/, 'deposit conversion must guard duplicate transfer block index');
  requireMatch(convertDepositToTokens, /claimedSet\.put\(blockIndex, true\)/, 'deposit conversion must record claimed block index');
  requireMatch(backend, /claimedDeposits := Iter\.toArray\(claimedSet\.keys\(\)\)/, 'preupgrade must persist claimed deposit indexes');
});

check('token spend routing debits once, opens a paid session, and records split/accounting surfaces', () => {
  requireMatch(spendTokensOnGame, /switch \(getOpenPaidGameSession\(caller, gameId\)\)[\s\S]*Session already open/, 'spend must reject duplicate open paid sessions');
  requireMatch(spendTokensOnGame, /let newBal = balance - amount;[\s\S]*tokens\.put\(caller, newBal\)/, 'spend must debit player token balance');
  requireMatch(spendTokensOnGame, /let isTicketGame = isTicketGameSubmission\(game\)/, 'spend must branch ticket vs regular games');
  requireMatch(spendTokensOnGame, /let creatorShare = if \(isTicketGame\) TICKET_GAME_CREATOR_SHARE else REGULAR_GAME_CREATOR_SHARE/, 'spend must use authoritative split constants');
  requireMatch(spendTokensOnGame, /royalties\.put\(game\.creator, currentRoyalty \+ creatorShareE8s\)/, 'spend must credit creator ICP-e8s earnings surface');
  requireMatch(spendTokensOnGame, /logRevenue\("gameplay", icpValueE8s, caller, 3\)/, 'spend must log gameplay revenue event in ICP e8s');
  requireMatch(spendTokensOnGame, /openPaidGameSession\(caller, gameId, amount\)/, 'spend must create paid session after accounting');
});

check('revenue split API and frontend IDL expose the same finished-product split fields', () => {
  const fields = [
    'ticketGameCreatorShare',
    'ticketGameDaoShare',
    'ticketGameBurnShare',
    'ticketGamePoolShare',
    'regularGameCreatorShare',
    'regularGameDaoShare',
    'regularGameBurnShare',
    'gameCreatorShare',
    'gameCreatorNonTicketShare',
    'nftCreatorShare',
  ];
  for (const field of fields) {
    assert.match(getRevenueSplits, new RegExp(`${field}\\s*:\\s*Nat`), `backend getRevenueSplits missing ${field}`);
    assert.match(frontendServiceBlock, new RegExp(`${field}:IDL\\.Nat`), `frontend getRevenueSplits IDL missing ${field}`);
  }
});

check('economy rate API and frontend IDL expose the same Phase 1 accounting invariant fields', () => {
  const fields = [
    'icpE8s',
    'tokensPerIcp',
    'ticketsPerIcp',
    'tokenE8s',
    'ticketE8s',
    'sellerPayout100TicketsE8s',
    'sellerPayout1000TicketsE8s',
  ];
  for (const field of fields) {
    assert.match(getEconomyRates, new RegExp(`${field}\\s*=|${field}\\s*:\\s*Nat`), `backend getEconomyRates missing ${field}`);
    assert.match(frontendServiceBlock, new RegExp(`${field}:IDL\\.Nat`), `frontend getEconomyRates IDL missing ${field}`);
  }
});

check('creator claim path uses ICP-e8s royalties/refunds, locks before await, and restores on transfer failure', () => {
  requireMatch(claimRoyalties, /let gameCreatorEarningsBalance = getGameCreatorEarningsBalance\(caller\)/, 'claim must include game creator earnings balance');
  requireMatch(claimRoyalties, /let nftSellerEarningsBalance = getNftSellerEarningsBalance\(caller\)/, 'claim must include NFT seller earnings balance');
  requireMatch(claimRoyalties, /let refundBalance = getRefundBalance\(caller\)/, 'claim must include separate refund balance');
  requireMatch(claimRoyalties, /royalties\.put\(caller, 0\)/, 'claim must lock royalties before ledger await');
  requireMatch(claimRoyalties, /nftSellerEarningsE8s\.put\(caller, 0\)/, 'claim must lock NFT seller earnings before ledger await');
  requireMatch(claimRoyalties, /refundsE8s\.put\(caller, 0\)/, 'claim must lock refunds before ledger await');
  const lockIndex = claimRoyalties.indexOf('royalties.put(caller, 0)');
  const awaitIndex = claimRoyalties.indexOf('await ICP_LEDGER.icrc1_transfer');
  assert.ok(lockIndex >= 0 && awaitIndex > lockIndex, 'claim must lock before ledger transfer await');
  requireMatch(claimRoyalties, /restoreGameCreatorEarningsBalance\(caller, gameCreatorEarningsBalance\)/, 'claim must restore game creator earnings on failure/trap');
  requireMatch(claimRoyalties, /restoreNftSellerEarningsBalance\(caller, nftSellerEarningsBalance\)/, 'claim must restore NFT seller earnings on failure/trap');
  requireMatch(claimRoyalties, /restoreRefundBalance\(caller, refundBalance\)/, 'claim must restore refunds on failure/trap');
});

check('treasury and audit/event visibility surfaces are present and frontend-gated when optional', () => {
  requireMatch(backend, /public shared\(_msg\) func getTreasuryBalance\(\) : async TreasuryBalanceSnapshot/, 'treasury balance surface must exist');
  requireMatch(backend, /public query func getRevenueLog\(\) : async \[RevenueEvent\]/, 'revenue event history must exist');
  requireMatch(backend, /public query func getRevenueSummary\(\) : async \[\(Text, Nat\)\]/, 'revenue summary must exist');
  requireMatch(frontend, /backendMethodAvailable\(be,'getTreasuryBalance'\)/, 'frontend must guard optional treasury balance calls');
  requireMatch(frontend, /OPTIONAL_BACKEND_METHODS_PENDING[\s\S]*'getTreasuryBalance'/, 'expected missing backend classifier must list treasury method');
});

check('frontend deposit and manual claim flows call the canonical backend methods and avoid legacy depositTokens', () => {
  requireMatch(frontend, /be\.convertDepositToTokens\(amountE8s\)/, 'frontend must use convertDepositToTokens');
  assert.doesNotMatch(frontend, /\.depositTokens\(/, 'frontend must not call disabled legacy depositTokens');
  requireMatch(frontend, /be\.claimRoyalties\(\)/, 'frontend must expose manual creator claim action');
});

const failures = [];
for (const [label, fn] of checks) {
  try {
    fn();
  } catch (error) {
    failures.push(`${label}: ${error.message}`);
  }
}

if (failures.length) {
  console.error(`Real ICP API-surface validation FAILED (${checks.length - failures.length}/${checks.length})`);
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`Real ICP API-surface validation PASSED (${checks.length}/${checks.length})`);
for (const [label] of checks) console.log(`PASS ${label}`);
