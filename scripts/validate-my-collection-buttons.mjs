import fs from 'node:fs';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const checks = [];

function check(name, pass) {
  checks.push({ name, pass: Boolean(pass) });
}

check('gashapon button has stable id', /id='gashaponTicketsBtn'[^>]*>Gashapon Tickets<\/button>/.test(html));
check('collection tab hides gashapon button', /gashaponBtn\.style\.display\s*=\s*tab==='collection'\?'none':'inline-block'/.test(html));
check('mint nft button is hidden by tab logic', /mintBtn\.style\.display\s*=\s*'none'/.test(html));
check('scan button remains visible on collection tab', /scanB\.style\.display\s*=\s*tab==='collection'\?'inline-block':'none'/.test(html));
check('collection button still opens collection tab', /showView\('prizes'\);showTab\('collection'\)/.test(html));

const failed = checks.filter(c => !c.pass);
for (const c of checks) console.log(`${c.pass ? '✅' : '❌'} ${c.name}`);

if (failed.length) {
  console.error(`My Collection button validation FAILED (${checks.length - failed.length}/${checks.length})`);
  process.exit(1);
}

console.log(`My Collection button validation PASSED (${checks.length}/${checks.length})`);
