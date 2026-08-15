import fs from 'node:fs';
import assert from 'node:assert/strict';

const index = fs.readFileSync('index.html', 'utf8');
const backend = fs.readFileSync('backend/main.mo', 'utf8');

function assertIncludes(source, needle, message) {
  assert.ok(source.includes(needle), message + `\nMissing: ${needle}`);
}

assertIncludes(backend, 'type TipReceipt = {', 'Backend exposes a stable TipReceipt model');
assertIncludes(backend, 'stable var tipReceiptEntries', 'Tip receipts are preserved in stable state');
assertIncludes(backend, 'public shared({ caller }) func recordIcpTip', 'Backend can record ICP tip receipts after transfer');
assertIncludes(backend, 'public query func getGameIcpTipSummary', 'Backend exposes tip summary query');
assertIncludes(backend, 'public query func getRecentGameIcpTips', 'Backend exposes recent tips query');

assertIncludes(index, 'const ICP_TIP_FEE_E8S = 10000n;', 'Frontend defines ICP ledger fee constant');
assertIncludes(index, 'const ICP_TIP_MIN_E8S = 10000n;', 'Frontend defines sane minimum tip constant');
assertIncludes(index, 'function icpToE8sInput(value)', 'Frontend parses decimal ICP inputs without floating point');
assertIncludes(index, 'recordIcpTip:IDL.Func', 'Backend IDL includes recordIcpTip');
assertIncludes(index, 'getGameIcpTipSummary:IDL.Func', 'Backend IDL includes tip summary');
assertIncludes(index, 'getRecentGameIcpTips:IDL.Func', 'Backend IDL includes recent tips');
assertIncludes(index, 'openIcpTipModal', 'The Back exposes ICP tip modal entrypoint');
assert.match(index, /id=["']icpTipAnonymous["'][^>]*checked/, 'Tip modal defaults arcade display to anonymous');
assertIncludes(index, 'On-chain transactions are public', 'Tip modal warns that public chain data remains visible');
assertIncludes(index, 'const ledger = await getLedgerActor(true);', 'ICP tip uses authenticated ledger actor');
assertIncludes(index, 'Principal.fromText(creatorPrincipalText)', 'ICP tip transfers directly to the game creator principal');
assertIncludes(index, 'await ledger.icrc1_transfer', 'ICP tip uses ICRC-1 transfer');
assertIncludes(index, 'await be.recordIcpTip', 'Backend receipt save happens after successful transfer code path');

const transferIndex = index.indexOf('await ledger.icrc1_transfer');
const receiptIndex = index.indexOf('await be.recordIcpTip');
assert.ok(transferIndex >= 0 && receiptIndex > transferIndex, 'Receipt recording must happen only after ledger transfer succeeds');

const forbiddenRecipientPatterns = [
  /to:\s*\{\s*owner:\s*Principal\.fromText\(BACKEND_CANISTER\)/,
  /to:\s*\{\s*owner:\s*Principal\.fromText\(['"]pifyq-raaaa-aaaab-agrqq-cai['"]\)/,
  /to:\s*\{\s*owner:\s*Principal\.fromText\(['"]mprew-viaaa-aaaah-quola-cai['"]\)/,
];
for (const pattern of forbiddenRecipientPatterns) {
  assert.ok(!pattern.test(index), `ICP tip recipient must not be backend/frontend/treasury: ${pattern}`);
}

console.log('ICP tip UI/backend contract checks passed');
