#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sourcePath = path.join(projectRoot, 'index.html');
const deployPath = path.join(projectRoot, '.deploy', 'frontend-public', 'index.html');

function readHtml(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function extractGetTreasuryBalanceRecord(source) {
  return source.match(/getTreasuryBalance\s*:\s*IDL\.Func\(\s*\[\s*\]\s*,\s*\[\s*IDL\.Record\(\s*\{([\s\S]*?)\}\s*\)\s*\]\s*,\s*\[\s*\]\s*\)/)?.[1] ?? '';
}

function hasTicketHolderLiabilityInTreasuryIdl(source) {
  const recordFields = extractGetTreasuryBalanceRecord(source);
  return /(?:^|[,\s])ticketHolderLiabilityE8s\s*:\s*IDL\.Nat(?:[,\s]|$)/.test(recordFields);
}

function validateHtml(filePath) {
  const source = readHtml(filePath);
  const normalized = source.replace(/\s+/g, ' ');

  return [
    {
      name: `${path.relative(projectRoot, filePath)} decodes ticketHolderLiabilityE8s in getTreasuryBalance Candid IDL`,
      ok: hasTicketHolderLiabilityInTreasuryIdl(source),
    },
    {
      name: `${path.relative(projectRoot, filePath)} shows readable Player-Held Ticket Liability label`,
      ok: /Player[-\s]Held Ticket Liability/i.test(normalized),
    },
    {
      name: `${path.relative(projectRoot, filePath)} explains player-held Tickets are already won by users`,
      ok: /Player[-\s]held Tickets are Tickets already won by users/i.test(normalized),
    },
    {
      name: `${path.relative(projectRoot, filePath)} explains player-held Tickets still need backing for NFT prizes`,
      ok: /still need backing because users can spend them on NFT prizes/i.test(normalized),
    },
    {
      name: `${path.relative(projectRoot, filePath)} does not imply Operating Treasury backs Tickets`,
      ok: !/Operating Treasury.{0,160}(backs?|backing|reserve|reserves|protected).{0,160}Tickets/i.test(normalized),
    },
    {
      name: `${path.relative(projectRoot, filePath)} keeps Operating Treasury separate from protected/backing math`,
      ok: /Operating Treasury[^`]*separate; not in protected backing math/i.test(source),
    },
  ];
}

const checks = [sourcePath, deployPath].flatMap(validateHtml);
const failures = checks.filter((check) => !check.ok);
if (failures.length) {
  console.error('FAIL: ticket-holder liability UI validation failed');
  for (const failure of failures) console.error(`- ${failure.name}`);
  process.exit(1);
}

console.log('PASS: ticket-holder liability UI validation passed');
