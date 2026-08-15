#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');
const backendPath = path.join(repoRoot, 'backend', 'main.mo');

function stripCommentsAndStrings(source) {
  let out = '';
  let i = 0;
  let blockDepth = 0;
  let inLine = false;
  let inString = false;
  let inChar = false;

  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];

    if (inLine) {
      if (ch === '\n') {
        inLine = false;
        out += ch;
      } else {
        out += ' ';
      }
      i += 1;
      continue;
    }

    if (blockDepth > 0) {
      if (ch === '/' && next === '*') {
        blockDepth += 1;
        out += '  ';
        i += 2;
      } else if (ch === '*' && next === '/') {
        blockDepth -= 1;
        out += '  ';
        i += 2;
      } else {
        out += ch === '\n' ? '\n' : ' ';
        i += 1;
      }
      continue;
    }

    if (inString) {
      if (ch === '\\') {
        out += '  ';
        i += 2;
      } else if (ch === '"') {
        inString = false;
        out += ' ';
        i += 1;
      } else {
        out += ch === '\n' ? '\n' : ' ';
        i += 1;
      }
      continue;
    }

    if (inChar) {
      if (ch === '\\') {
        out += '  ';
        i += 2;
      } else if (ch === "'") {
        inChar = false;
        out += ' ';
        i += 1;
      } else {
        out += ch === '\n' ? '\n' : ' ';
        i += 1;
      }
      continue;
    }

    if (ch === '/' && next === '/') {
      inLine = true;
      out += '  ';
      i += 2;
    } else if (ch === '/' && next === '*') {
      blockDepth = 1;
      out += '  ';
      i += 2;
    } else if (ch === '"') {
      inString = true;
      out += ' ';
      i += 1;
    } else if (ch === "'") {
      inChar = true;
      out += ' ';
      i += 1;
    } else {
      out += ch;
      i += 1;
    }
  }

  return out;
}

function findBalancedSection(source, startIndex, openChar = '{', closeChar = '}') {
  const openIndex = source.indexOf(openChar, startIndex);
  if (openIndex < 0) return '';

  let depth = 0;
  for (let i = openIndex; i < source.length; i += 1) {
    if (source[i] === openChar) depth += 1;
    if (source[i] === closeChar) depth -= 1;
    if (depth === 0) return source.slice(startIndex, i + 1);
  }
  return '';
}

function getFunctionSection(source, name) {
  const match = new RegExp(`(?:public\\s+shared(?:\\([^)]*\\))?\\s+)?func\\s+${name}\\b`).exec(source);
  if (!match) return '';
  return findBalancedSection(source, match.index);
}

function getTypeRecordSection(source, name) {
  const match = new RegExp(`type\\s+${name}\\s*=\\s*\\{`).exec(source);
  if (!match) return '';
  return findBalancedSection(source, match.index);
}

function hasWord(source, word) {
  return new RegExp(`\\b${word}\\b`).test(source);
}

function pass(label, details = '') {
  return { ok: true, label, details };
}

function fail(label, details) {
  return { ok: false, label, details };
}

if (!fs.existsSync(backendPath)) {
  console.error(`FAIL backend source exists :: missing ${backendPath}`);
  process.exit(2);
}

const rawSource = fs.readFileSync(backendPath, 'utf8');
const source = stripCommentsAndStrings(rawSource);
const treasuryBalanceType = getTypeRecordSection(source, 'TreasuryBalanceSnapshot');
const getTreasuryBalance = getFunctionSection(source, 'getTreasuryBalance');
const getTreasuryLaneSnapshot = getFunctionSection(source, 'getTreasuryLaneSnapshot');
const outstandingTicketsHelper = getFunctionSection(source, 'totalOutstandingTickets')
  || getFunctionSection(source, 'totalPlayerHeldTickets')
  || getFunctionSection(source, 'totalTicketHolderLiabilityTickets');

const checks = [];

if (outstandingTicketsHelper) {
  const totalsRuntimeTickets = /for\s*\([^)]*\bin\s+tickets\.entries\s*\(\s*\)/s.test(outstandingTicketsHelper)
    || /Iter\.toArray\s*\(\s*tickets\.entries\s*\(\s*\)\s*\)/s.test(outstandingTicketsHelper);
  const totalsStableTickets = /for\s*\([^)]*\bin\s+ticketEntries\.(?:vals|entries)\s*\(\s*\)/s.test(outstandingTicketsHelper)
    || hasWord(outstandingTicketsHelper, 'ticketEntries');
  const accumulatesAmounts = /total\s*(?::\s*Nat)?\s*=\s*0/s.test(outstandingTicketsHelper)
    && /total\s*\+=\s*\w+/s.test(outstandingTicketsHelper)
    && /total\s*;?\s*\}/s.test(outstandingTicketsHelper);
  checks.push(
    totalsRuntimeTickets && totalsStableTickets && accumulatesAmounts
      ? pass('player-held Ticket total helper', 'found helper that totals runtime tickets and stable ticketEntries')
      : fail('player-held Ticket total helper', 'helper name found, but it does not clearly total runtime tickets and stable ticketEntries')
  );
} else {
  checks.push(fail('player-held Ticket total helper', 'missing totalOutstandingTickets()/equivalent helper for player-held Tickets'));
}

const fieldPresent = hasWord(treasuryBalanceType, 'ticketHolderLiabilityE8s');
const calculationPresent = /(?:let\s+)?ticketHolderLiabilityE8s\s*=\s*(?:totalOutstandingTickets|totalPlayerHeldTickets|totalTicketHolderLiabilityTickets)\s*\(\s*\)\s*\*\s*TICKET_LIABILITY_E8S/s.test(getTreasuryBalance);
checks.push(
  fieldPresent && calculationPresent
    ? pass('ticketHolderLiabilityE8s field/calculation', 'snapshot field and getTreasuryBalance calculation found')
    : fail('ticketHolderLiabilityE8s field/calculation', `missing ${fieldPresent ? 'calculation in getTreasuryBalance' : 'TreasuryBalanceSnapshot field'}${!fieldPresent && !calculationPresent ? ' and calculation in getTreasuryBalance' : ''}`)
);

const requiredReservedTerms = [
  'tokenLiabilityE8s',
  'royaltyLiabilityE8s',
  'refundLiabilityE8s',
  'ticketPoolLiabilityE8s',
  'ticketHolderLiabilityE8s',
];
const reservedAssignment = getTreasuryBalance.match(/let\s+reservedE8s\s*=([\s\S]*?);/)?.[1] ?? '';
const missingReservedTerms = requiredReservedTerms.filter((term) => !hasWord(reservedAssignment, term));
checks.push(
  missingReservedTerms.length === 0
    ? pass('reservedE8s includes all protected liabilities', requiredReservedTerms.join(', '))
    : fail('reservedE8s includes all protected liabilities', `missing from reservedE8s: ${missingReservedTerms.join(', ')}`)
);

const laneUsesTreasuryBalance = hasWord(getTreasuryLaneSnapshot, 'getTreasuryBalance')
  && /protectedBalanceE8s\s*=\s*treasury\.balanceE8s/s.test(getTreasuryLaneSnapshot)
  && /protectedReservedE8s\s*=\s*treasury\.reservedE8s/s.test(getTreasuryLaneSnapshot)
  && /\b(?:protectedWithdrawableE8s|backendSafeWithdrawableE8s)\s*=\s*treasury\.withdrawableE8s/s.test(getTreasuryLaneSnapshot);
checks.push(
  laneUsesTreasuryBalance
    ? pass('getTreasuryLaneSnapshot derives protected values from getTreasuryBalance', 'protected values use treasury snapshot')
    : fail('getTreasuryLaneSnapshot derives protected values from getTreasuryBalance', 'protected balance/reserved/withdrawable are not clearly sourced from getTreasuryBalance()')
);

const mainTreasuryBalanceQuery = /icrc1_balance_of\s*\(\s*\{\s*owner\s*=\s*selfPrincipal\s*;\s*subaccount\s*=\s*null\s*\}\s*\)/s.test(getTreasuryBalance);
const operatingSubaccountInTreasuryBalance = hasWord(getTreasuryBalance, 'OPERATING_TREASURY_SUBACCOUNT');
const operatingQueriedSeparately = /icrc1_balance_of\s*\(\s*\{\s*owner\s*=\s*selfPrincipal\s*;\s*subaccount\s*=\s*\?OPERATING_TREASURY_SUBACCOUNT\s*\}\s*\)/s.test(getTreasuryLaneSnapshot)
  && /operatingIncludedInBacking\s*=\s*false/s.test(getTreasuryLaneSnapshot)
  && /operatingIncludedInBackendSafeMath\s*=\s*false/s.test(getTreasuryLaneSnapshot);
checks.push(
  mainTreasuryBalanceQuery && !operatingSubaccountInTreasuryBalance && operatingQueriedSeparately
    ? pass('Operating Treasury excluded from getTreasuryBalance', 'main treasury uses subaccount=null; operating lane is queried separately and marked excluded')
    : fail('Operating Treasury excluded from getTreasuryBalance', 'getTreasuryBalance must use main account only and must not reference OPERATING_TREASURY_SUBACCOUNT')
);

let failures = 0;
for (const check of checks) {
  const status = check.ok ? 'PASS' : 'FAIL';
  console.log(`${status} ${check.label} :: ${check.details}`);
  if (!check.ok) failures += 1;
}

if (failures > 0) {
  console.log(`\nFAIL ticket-holder liability solvency validator: ${failures} missing requirement(s).`);
  process.exit(1);
}

console.log('\nPASS ticket-holder liability solvency validator: backend source includes player-held Ticket liability in protected treasury math.');
