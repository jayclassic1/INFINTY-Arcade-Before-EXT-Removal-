import { readFileSync } from 'node:fs';

const source = readFileSync('backend/main.mo', 'utf8');

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function pass(message) {
  console.log(`PASS: ${message}`);
}

function assert(condition, message) {
  if (condition) pass(message);
  else fail(message);
}

function extractBalancedBlock(text, startIndex) {
  const firstBrace = text.indexOf('{', startIndex);
  if (firstBrace === -1) return '';
  let depth = 0;
  for (let i = firstBrace; i < text.length; i++) {
    const ch = text[i];
    if (ch === '{') depth++;
    if (ch === '}') {
      depth--;
      if (depth === 0) return text.slice(firstBrace, i + 1);
    }
  }
  return '';
}

const methodMatch = source.match(/public\s+shared\s*\(msg\)\s+func\s+adminWithdrawOperatingTreasuryToAccountId\s*\(\s*toAccountHex\s*:\s*Text\s*,\s*amountE8s\s*:\s*Nat\s*\)\s*:\s*async\s+Result\.Result\s*<\s*Nat\s*,\s*Text\s*>/);
assert(methodMatch, 'adminWithdrawOperatingTreasuryToAccountId(Text, Nat) -> Result Nat/Text exists');

const methodBody = methodMatch ? extractBalancedBlock(source, methodMatch.index) : '';
assert(/not\s+isAdmin\s*\(\s*msg\.caller\s*\)/.test(methodBody), 'method requires admin caller');
assert(/hexToBlob\s*\(\s*toAccountHex\s*\)/.test(methodBody), 'method validates destination through hexToBlob(toAccountHex)');
assert(/from_subaccount\s*=\s*\?OPERATING_TREASURY_SUBACCOUNT/.test(methodBody), 'classic transfer source is ?OPERATING_TREASURY_SUBACCOUNT');
assert(/\.transfer\s*\(\s*\{[\s\S]*to\s*=\s*(?:destinationBlob|_dest|dest)[\s\S]*fee\s*=\s*\{\s*e8s\s*=\s*10_000[\s\S]*memo\s*=\s*0[\s\S]*created_at_time\s*=\s*null[\s\S]*amount\s*=\s*\{\s*e8s\s*=\s*Nat64\.fromNat\s*\(\s*amountE8s\s*\)/.test(methodBody), 'method uses classic ledger transfer to raw account-id Blob with fee/memo/timestamp requirements');
assert(!/icrc1_transfer\s*\(/.test(methodBody), 'account-id method does not use icrc1_transfer');
assert(/operatingTreasuryWithdrawalInFlight/.test(methodBody), 'method reuses operatingTreasuryWithdrawalInFlight guard');
assert(/icrc1_balance_of\s*\(\s*\{\s*owner\s*=\s*selfPrincipal\s*;\s*subaccount\s*=\s*\?OPERATING_TREASURY_SUBACCOUNT\s*\}\s*\)/.test(methodBody), 'method checks Operating Treasury balance only');
assert(/amountE8s\s*\+\s*ICP_LEDGER_FEE_E8S/.test(methodBody), 'method requires amount plus ledger fee availability');

const treasuryBalanceMatch = source.match(/public\s+shared\s+query\s+func\s+getTreasuryBalance\s*\(/) || source.match(/public\s+query\s+func\s+getTreasuryBalance\s*\(/) || source.match(/func\s+getTreasuryBalance\s*\(/);
const treasuryBalanceBody = treasuryBalanceMatch ? extractBalancedBlock(source, treasuryBalanceMatch.index) : '';
assert(treasuryBalanceBody && !/OPERATING_TREASURY/.test(treasuryBalanceBody), 'getTreasuryBalance remains protected/backing only and does not reference operating treasury');
assert(/public\s+shared\s*\(msg\)\s+func\s+adminWithdrawOperatingTreasury\s*\(\s*destination\s*:\s*Account\s*,\s*amountE8s\s*:\s*Nat\s*\)/.test(source), 'existing adminWithdrawOperatingTreasury(destination : Account, amountE8s : Nat) remains available');

if (process.exitCode) process.exit(process.exitCode);
console.log('Operating Treasury account-id backend validation passed.');
