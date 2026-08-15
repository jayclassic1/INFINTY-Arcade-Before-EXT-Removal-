import fs from 'node:fs';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const checks = [];

function check(name, pass) {
  checks.push({ name, pass: Boolean(pass) });
}

check('top ICP balance chip has stable id and opens wallet panel', /<div[^>]*id=['"]topIcpChip['"][^>]*onclick=['"]openTopIcpWalletChip\(this\)['"][^>]*>/.test(html));
check('top ICP balance refresh control remains present', /id=['"]topIcpRefresh['"][^>]*onclick=['"]refreshIcpBtn\(this,\s*event\)['"]/.test(html));
check('refresh handler accepts event argument', /async\s+function\s+refreshIcpBtn\s*\(\s*el\s*,\s*evt\s*\)/.test(html));
check('refresh handler stops propagation before refreshing', /evt\?\.stopPropagation\(\)/.test(html) || /if\s*\(\s*evt\s*\)\s*evt\.stopPropagation\(\)/.test(html));
check('wallet chip click helper exists', /function\s+openTopIcpWalletChip\s*\(\s*chip\s*\)/.test(html));
check('wallet chip click helper opens existing wallet panel', /function\s+openTopIcpWalletChip[\s\S]*openWalletPanel\(\)/.test(html));
check('wallet chip animation css exists', /\.icp-chip-hit[\s\S]*animation\s*:\s*icpChipHit/.test(html));
check('refresh animation css exists', /\.icp-refresh-hit[\s\S]*animation\s*:\s*icpRefreshHit/.test(html));
check('wallet panel Scan button remains present', /id=['"]walletScanBtn['"][^>]*onclick=['"]scanWalletBtn\(\)['"][^>]*>Scan<\/button>/.test(html));
check('prize booth collection Scan button remains present', /id=['"]scanBtn['"][^>]*onclick=['"]renderCollection\(true\)['"][^>]*>Scan<\/button>/.test(html));

const failed = checks.filter(c => !c.pass);
for (const c of checks) console.log(`${c.pass ? '✅' : '❌'} ${c.name}`);

if (failed.length) {
  console.error(`Wallet balance chip validation FAILED (${checks.length - failed.length}/${checks.length})`);
  process.exit(1);
}

console.log(`Wallet balance chip validation PASSED (${checks.length}/${checks.length})`);
