import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, '..');

const read = (rel) => readFileSync(resolve(projectRoot, rel), 'utf8');
const exists = (rel) => existsSync(resolve(projectRoot, rel));

const files = {
  index: read('index.html'),
  backend: read('backend/main.mo'),
  packageJson: read('package.json'),
  deployIndex: exists('.deploy/frontend-public/index.html') ? read('.deploy/frontend-public/index.html') : '',
  runbook: exists('docs/runbooks/2026-04-30-phase3-dao-jackpot-funding-rule.md')
    ? read('docs/runbooks/2026-04-30-phase3-dao-jackpot-funding-rule.md')
    : '',
};

const htmlTargets = [
  ['index.html', files.index],
  ['.deploy/frontend-public/index.html', files.deployIndex],
].filter(([, body]) => body.length > 0);

const failures = [];
const requireMatch = (label, body, pattern) => {
  if (!pattern.test(body)) failures.push(`missing ${label}`);
};
const forbidMatch = (label, body, pattern) => {
  if (pattern.test(body)) failures.push(`forbidden ${label}`);
};

const staleStandaloneClaims = [
  ['NFT/non-game 50% burned / 50% DAO claim', /50%\s+burned\s*[·•-]\s*50%\s+(?:to\s+)?DAO/i],
  ['nearly half of revenue to DAO members claim', /nearly\s+half\s+(?:of\s+)?(?:our\s+)?revenue\s+goes\s+to\s+(?:our\s+)?DAO\s+members/i],
  ['community kickbacks copy', /community\s+kickbacks/i],
  ['raw broad-revenue DAO teaser', /Live\s+balances,\s*revenue\s+sources,\s*lottery\s+history/i],
];

const nonGameFundingContexts = [
  'NFT mint',
  'mint fee',
  'listing fee',
  'showroom fee',
  'showroom application',
  'gashapon',
  'artist marketplace',
  'creator payout',
  'seller proceed',
  'token deposit',
  'admin credit',
  'treasury sweep',
  'withdrawal',
  'refund',
  'platform fee',
];

const broadDaoFundingPattern = /(?:50%\s+(?:to\s+)?DAO|half\s+(?:to\s+)?DAO|DAO\s+(?:jackpot|reward|member\s+reward)[^.\n]{0,120}\b(?:funded|funding|receives?|gets?)|(?:funded|funding|receives?|gets?)[^.\n]{0,120}\bDAO\s+(?:jackpot|reward|member\s+reward))/i;
const exclusionOrGuardPattern = /\b(?:not\s+funded|do\s+not\s+fund|does\s+not\s+fund|must\s+not|not\s+DAO|not\s+described\s+as|not\s+routed)\b/i;

function findNonGameFundingClaims(body, context) {
  const lowerBody = body.toLowerCase();
  const needle = context.toLowerCase();
  const claims = [];
  let index = 0;
  while ((index = lowerBody.indexOf(needle, index)) !== -1) {
    const start = Math.max(0, index - 220);
    const end = Math.min(body.length, index + context.length + 220);
    const snippet = body.slice(start, end);
    if (broadDaoFundingPattern.test(snippet) && !exclusionOrGuardPattern.test(snippet)) {
      claims.push(snippet.replace(/\s+/g, ' ').trim().slice(0, 180));
    }
    index += needle.length;
  }
  return claims;
}

for (const [rel, body] of htmlTargets) {
  for (const [label, pattern] of staleStandaloneClaims) forbidMatch(`${rel}: ${label}`, body, pattern);

  for (const context of nonGameFundingContexts) {
    const claims = findNonGameFundingClaims(body, context);
    if (claims.length) failures.push(`forbidden ${rel}: non-game DAO jackpot/reward funding context (${context}): ${claims[0]}`);
  }

  requireMatch(`${rel}: game-earned DAO dashboard header`, body, /Live\s+game-earned\s+DAO\s+treasury,\s+jackpot,\s+and\s+governance\s+stats/i);
  requireMatch(`${rel}: game-earned DAO treasury card label`, body, /GAME-EARNED\s+DAO\s+TREASURY/i);
  requireMatch(`${rel}: game-earned DAO jackpot card label`, body, /GAME-EARNED\s+DAO\s+JACKPOT/i);
  requireMatch(`${rel}: gameplay-funded DAO rewards manifesto copy`, body, /gameplay-funded\s+DAO\s+rewards/i);
  requireMatch(`${rel}: NFT/listing/gashapon exclusion copy`, body, /not\s+funded\s+by\s+NFT\s+minting,\s+listings,\s+gashapon,\s+or\s+artist\s+marketplace\s+revenue/i);
  requireMatch(`${rel}: gaming source allowlist`, body, /const\s+DAO_GAMING_REWARD_SOURCE_LABELS\s*=\s*Object\.freeze\(\{/);
  requireMatch(`${rel}: gameplay source allowlisted`, body, /'gameplay'\s*:\s*'Gameplay'/);
  requireMatch(`${rel}: game-purchase source allowlisted`, body, /'game-purchase'\s*:\s*'Game Purchase'/);
  requireMatch(`${rel}: game-demo source allowlisted`, body, /'game-demo'\s*:\s*'Game Demo'/);
}

const allowlistMatch = files.index.match(/const\s+DAO_GAMING_REWARD_SOURCE_LABELS\s*=\s*Object\.freeze\(\{[\s\S]*?\}\);/);
const allowlist = allowlistMatch?.[0] ?? '';
for (const blocked of ['nft', 'mint', 'listing', 'showroom', 'gashapon', 'deposit', 'admin', 'treasury', 'sweep', 'refund', 'withdrawal', 'artist', 'seller', 'platform']) {
  forbidMatch(`non-game source '${blocked}' in DAO reward source allowlist`, allowlist, new RegExp(blocked, 'i'));
}

requireMatch('backend gameplay-only ticket DAO split comment', files.backend, /Ticket\s+games:\s+20%\s+to\s+game\s+dev,\s+70%\s+to\s+game\s+ticket\s+pool,\s+5%\s+DAO\s+gaming\s+rewards,\s+5%\s+burn/i);
requireMatch('backend gameplay-only regular game DAO split comment', files.backend, /Regular\/non-ticket\s+games:\s+80%\s+to\s+game\s+dev,\s+10%\s+DAO\s+gaming\s+rewards,\s+10%\s+burn/i);
requireMatch('backend NFT treasury is not DAO rewards comment', files.backend, /NFT\s+sales:\s+90%\s+to\s+NFT\s+creator,\s+10%\s+stays\s+in\s+operating\s+treasury;\s+not\s+DAO\s+jackpot\s+or\s+member\s+reward\s+funding/i);
requireMatch('backend revenue log distinguishes platform-wide accounting', files.backend, /Platform-wide\s+revenue\s+event\s+log;\s+this\s+is\s+not\s+DAO\s+reward\s+accounting/i);
requireMatch('backend total revenue distinguishes platform-wide accounting', files.backend, /Platform-wide\s+total\s+revenue\s+collected.*not\s+DAO\s+reward\s+accounting/i);

requireMatch('package script wires validator', files.packageJson, /"validate:dao-jackpot-funding-rule"\s*:\s*"node\s+scripts\/validate-dao-jackpot-funding-rule\.mjs"/);

requireMatch('Phase 3 runbook exists with game-earned rule', files.runbook, /DAO\s+jackpot\/reward\s+pool\s+is\s+game-earned\s+only/i);
requireMatch('Phase 3 runbook lists hard exclusions', files.runbook, /Hard\s+exclusions[\s\S]*NFT\s+mint[\s\S]*listing[\s\S]*deposits[\s\S]*refunds[\s\S]*treasury\s+movements/i);
requireMatch('Phase 3 runbook preserves audit accounting caveat', files.runbook, /Preserve\s+platform-wide\s+audit\s+logs/i);

if (failures.length) {
  console.error('DAO jackpot funding rule validation failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log('DAO jackpot funding rule validation passed');
