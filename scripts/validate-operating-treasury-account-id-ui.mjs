import { readFileSync } from 'node:fs';

const html = readFileSync('index.html', 'utf8');

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

assert(/Destination Account ID/i.test(html), 'UI labels the primary field Destination Account ID');
assert(/64-character (?:ICP )?account ID/i.test(html) && /4124447f786d4f994a51581bde316bd383a634f92e60df6c9b7453db16ec4206/.test(html), 'UI includes clear 64-character account ID guidance and Jay-style example');
assert(/adminWithdrawOperatingTreasuryToAccountId\s*:\s*IDL\.Func\s*\(\s*\[\s*IDL\.Text\s*,\s*IDL\.Nat\s*\]\s*,\s*\[\s*ResultNat\s*\]/.test(html), 'backend IDL exposes adminWithdrawOperatingTreasuryToAccountId(Text, Nat) -> ResultNat');
assert(/adminWithdrawOperatingTreasuryToAccountId\s*\(\s*destInput\s*,\s*amountE8s\s*\)/.test(html), 'account-id path calls adminWithdrawOperatingTreasuryToAccountId(accountIdHex, amountE8s)');
assert(/Principal default account/i.test(html) && /principalToAccountHex\s*\(\s*destInput\s*\)/.test(html), 'principal fallback previews derived default account ID before sending');
assert(/destination type/i.test(html) && /exact receiving account ID/i.test(html), 'confirmation shows destination type and exact receiving account ID');
assert(/ledger fee/i.test(html), 'confirmation includes ledger fee note');
assert(/Operating Treasury only/.test(html), 'confirmation warns Operating Treasury only');
assert(/Protected\s*\/\s*Backing Treasury is untouched/.test(html), 'confirmation warns Protected / Backing Treasury is untouched');
assert(!/principal (?:is|equals|matches) (?:your )?(?:wallet )?account ID/i.test(html), 'UI does not imply principal equals wallet account ID');
assert(!/Principal\.fromText\s*\(\s*destInput\s*\)[\s\S]{0,400}adminWithdrawOperatingTreasuryToAccountId/.test(html), 'account-id withdrawal is not blocked by principal parsing');

if (process.exitCode) process.exit(process.exitCode);
console.log('Operating Treasury account-id UI validation passed.');
