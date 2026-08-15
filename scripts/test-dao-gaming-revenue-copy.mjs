import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, '..');
const indexHtml = readFileSync(resolve(projectRoot, 'index.html'), 'utf8');
const notes = readFileSync(resolve(projectRoot, 'docs/plans/2026-04-29-dao-revenue-change-notes.md'), 'utf8');

const backend = readFileSync(resolve(projectRoot, 'backend/main.mo'), 'utf8');

const daoDashboardBlock = indexHtml.match(/async function loadDaoDashboard\(\)\{[\s\S]*?\n\}/)?.[0] ?? '';
const daoTreasuryAdminBlock = indexHtml.match(/async function loadDaoTreasuryAdmin\(\)\{[\s\S]*?\n\}/)?.[0] ?? '';
const daoRevenueContexts = `${daoDashboardBlock}\n${daoTreasuryAdminBlock}`;
const daoGamingSourceConstMatch = indexHtml.match(/const DAO_GAMING_REWARD_SOURCE_LABELS\s*=\s*Object\.freeze\(\{[\s\S]*?\}\);/);
const daoGamingSourceConst = daoGamingSourceConstMatch?.[0] ?? '';

const forbiddenDaoSourceLabels = [
  'NFT Listing',
  'User-Minted Listing',
  'NFT Sale',
  'Gashapon (General)',
  'Gashapon (Category)',
  'User Mint',
  'Game Removal',
];

const forbiddenIndexClaims = [
  ['creator ticket split says raw DAO share', /70% into the ticket pool · 5% DAO · 5% burned/],
  ['creator non-ticket split says raw DAO share', /80%<\/b> of tokens inserted goes to you · 10% DAO · 10% burned/],
  ['removed game pool goes to DAO treasury', /50% burned · 50% to DAO treasury/],
  ['manifesto says nearly half revenue goes to DAO members', /nearly half our Revenue goes to our DAO Members/],
  ['weekly draw says all tokens or tickets are auto-deposited to DAO members', /Tokens\/Tickets are auto deposited to randomized DAO Members/],
  ['mint token confirmation says 50% to DAO', /20 Tokens will be deducted\.<br>50% burned · 50% to DAO/],
  ['mint ticket confirmation says 50% to DAO', /100 Tickets will be deducted\.<br>50% burned · 50% to DAO/],
  ['generic community kickbacks phrase remains', /community kickbacks/i],
  ['DAO Treasury teaser still advertises broad revenue sources', /DAO TREASURY[\s\S]{0,500}Live balances, revenue sources, lottery history/],
];

const requiredIndexClaims = [
  ['ticket gameplay share labels DAO gaming rewards', /70% into the ticket pool · 5% DAO gaming rewards · 5% burned/],
  ['non-ticket gameplay share labels DAO gaming rewards', /80%<\/b> of tokens inserted goes to you · 10% DAO gaming rewards · 10% burned/],
  ['game removal preserves game pools without DAO treasury drain', /remaining backed ticket pool stays reserved for that game economy; it is not redirected to DAO rewards/i],
  ['manifesto says DAO rewards are game-earned/gameplay-funded', /gameplay-funded DAO rewards are game-earned only/i],
  ['weekly draw says gaming-funded DAO rewards', /gaming-funded DAO rewards draw/i],
  ['mint token confirmation excludes DAO funding', /20 Tokens will be deducted\.<br>Mint fees are burned or retained by the platform; they do not fund DAO rewards\./],
  ['mint ticket confirmation excludes DAO funding', /100 Tickets will be deducted\.<br>Mint fees are burned or retained by the platform; they do not fund DAO rewards\./],
];

const requiredIndexStructure = [
  ['central DAO gaming source allowlist exists', /const DAO_GAMING_REWARD_SOURCE_LABELS\s*=\s*Object\.freeze\(\{/],
  ['central source allowlist documents gaming-only policy', /Only gaming reward sources are allowed in DAO dashboard\/treasury revenue tables/],
  ['dashboard uses central source allowlist', /Object\.prototype\.hasOwnProperty\.call\(DAO_GAMING_REWARD_SOURCE_LABELS, src\)/],
  ['legacy getRevenueSplitConfig is documented as stale compatibility', /Legacy compatibility surface: getRevenueSplitConfig keeps old field names[\s\S]{0,500}userMintDaoShare[\s\S]{0,500}must not be rendered as active DAO reward policy/],
];

const requiredCentralGamingSources = [
  ['gameplay source is allowed', /'gameplay'\s*:\s*'Gameplay'/],
  ['game purchase source is allowed', /'game-purchase'\s*:\s*'Game Purchase'/],
  ['game demo source is allowed', /'game-demo'\s*:\s*'Game Demo'/],
];

const requiredBackendNotes = [
  ['backend revenue log is labeled platform-wide not DAO reward accounting', /Platform-wide revenue event log; this is not DAO reward accounting/i],
  ['backend total revenue is labeled platform-wide not DAO reward accounting', /Platform-wide total revenue collected/i],
];

const requiredNotes = [
  ['decision marked confirmed', /## Confirmed Decision/],
  ['confirmed DAO gameplay share', /DAO keeps its gameplay revenue share/i],
  ['confirmed no NFT or gashapon DAO funding', /NFT, listing, mint, artist\/seller, token-purchase, and gashapon commerce do not fund DAO rewards/i],
  ['phase 2 findings distinguish active accounting from stale compatibility', /Phase 2 Findings[\s\S]*Actual accounting[\s\S]*Stale compatibility/i],
];

const failures = [];
for (const [label, pattern] of forbiddenIndexClaims) {
  if (pattern.test(indexHtml)) failures.push(`forbidden index claim remains: ${label}`);
}
for (const staleLabel of forbiddenDaoSourceLabels) {
  if (daoRevenueContexts.includes(staleLabel)) {
    failures.push(`stale DAO dashboard/admin non-gaming source label remains: ${staleLabel}`);
  }
}
for (const [label, pattern] of requiredIndexClaims) {
  if (!pattern.test(indexHtml)) failures.push(`missing required index claim: ${label}`);
}
for (const [label, pattern] of requiredIndexStructure) {
  if (!pattern.test(indexHtml)) failures.push(`missing required index structure: ${label}`);
}
for (const [label, pattern] of requiredCentralGamingSources) {
  if (!pattern.test(daoGamingSourceConst)) failures.push(`missing central DAO gaming source: ${label}`);
}
for (const staleLabel of forbiddenDaoSourceLabels) {
  if (daoGamingSourceConst.includes(staleLabel)) {
    failures.push(`stale non-gaming label is present in central DAO gaming source allowlist: ${staleLabel}`);
  }
}
for (const [label, pattern] of requiredBackendNotes) {
  if (!pattern.test(backend)) failures.push(`missing required backend note: ${label}`);
}
for (const [label, pattern] of requiredNotes) {
  if (!pattern.test(notes)) failures.push(`missing required notes update: ${label}`);
}

if (failures.length) {
  console.error('DAO gaming-only revenue copy test failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log('DAO gaming-only revenue copy test passed');
