import fs from 'node:fs';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const checks = [];
const check = (name, pass) => checks.push({ name, pass: Boolean(pass) });

check('wallet MAX button calls fillMaxWithdraw', /onclick=['"]fillMaxWithdraw\(\)['"]/.test(html));
check('fillMaxWithdraw function exists', /function\s+fillMaxWithdraw\s*\(/.test(html));
check('fillMaxWithdraw is exported to window for inline onclick handlers', /\['fillMaxWithdraw',\s*fillMaxWithdraw\]/.test(html));
check('fillMaxWithdraw targets both wallet amount inputs', /#withdrawAmount,#withdrawAmt/.test(html));
check('wallet scan function remains exported', /\['scanWalletBtn',\s*scanWalletBtn\]/.test(html));

const failed = checks.filter(c => !c.pass);
for (const c of checks) console.log(`${c.pass ? '✅' : '❌'} ${c.name}`);
if (failed.length) {
  console.error(`Wallet globals validation FAILED (${checks.length - failed.length}/${checks.length})`);
  process.exit(1);
}
console.log(`Wallet globals validation PASSED (${checks.length}/${checks.length})`);
