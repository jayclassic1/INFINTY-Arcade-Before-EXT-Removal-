#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const backend = readFileSync(join(root, 'backend', 'main.mo'), 'utf8');
const docs = readFileSync(join(root, 'docs', 'plans', '2026-05-09-nft-seller-payout-phase1-accounting-invariant.md'), 'utf8');

const checks = [];
function check(name, fn) {
  checks.push([name, fn]);
}

function natConst(name) {
  const literal = backend.match(new RegExp(`transient\\s+let\\s+${name}\\s*:\\s*Nat\\s*=\\s*([0-9_]+)\\b`));
  if (literal) return Number(literal[1].replaceAll('_', ''));
  const derived = backend.match(new RegExp(`transient\\s+let\\s+${name}\\s*:\\s*Nat\\s*=\\s*(\\w+)\\s*\\/\\s*(\\w+)\\s*;`));
  assert.ok(derived, `${name} Nat constant missing`);
  return natConst(derived[1]) / natConst(derived[2]);
}

check('backend centralizes fixed ICP e8s/token/ticket rates', () => {
  assert.equal(natConst('ICP_E8S'), 100_000_000);
  assert.equal(natConst('TOKENS_PER_ICP'), 100);
  assert.equal(natConst('TICKETS_PER_ICP'), 1_000);
  assert.equal(natConst('TOKEN_LIABILITY_E8S'), 1_000_000);
  assert.equal(natConst('TICKET_LIABILITY_E8S'), 100_000);
});

check('backend keeps token/ticket liabilities aligned to canonical rates', () => {
  assert.equal(natConst('TOKEN_LIABILITY_E8S'), natConst('ICP_E8S') / natConst('TOKENS_PER_ICP'));
  assert.equal(natConst('TICKET_LIABILITY_E8S'), natConst('ICP_E8S') / natConst('TICKETS_PER_ICP'));
});

check('backend exposes pure seller payout helper with fixed-rate ticket math', () => {
  assert.match(backend, /func\s+ticketCostToSellerPayoutE8s\s*\(\s*ticketCost\s*:\s*Nat\s*\)\s*:\s*Nat\s*{\s*ticketCost\s*\*\s*TICKET_LIABILITY_E8S\s*;\s*}/);
});

check('backend proves canonical examples through a query surface', () => {
  assert.match(backend, /type\s+EconomyRates\s*=\s*{[\s\S]*tokensPerIcp\s*:\s*Nat[\s\S]*ticketsPerIcp\s*:\s*Nat[\s\S]*ticketE8s\s*:\s*Nat[\s\S]*sellerPayout100TicketsE8s\s*:\s*Nat[\s\S]*sellerPayout1000TicketsE8s\s*:\s*Nat[\s\S]*}/);
  assert.match(backend, /public\s+query\s+func\s+getEconomyRates\s*\(\s*\)\s*:\s*async\s+EconomyRates/);
  assert.match(backend, /sellerPayout100TicketsE8s\s*=\s*ticketCostToSellerPayoutE8s\(100\)/);
  assert.match(backend, /sellerPayout1000TicketsE8s\s*=\s*ticketCostToSellerPayoutE8s\(1000\)/);
});

check('fixed-rate seller payout examples cannot drift', () => {
  const ticketE8s = natConst('TICKET_LIABILITY_E8S');
  assert.equal(100 * ticketE8s, 10_000_000);
  assert.equal(1_000 * ticketE8s, 100_000_000);
});

check('fixed-rate seller payout helper is the only ticket-to-ICP conversion source', () => {
  assert.match(backend, /let sellerPayoutE8s = ticketCostToSellerPayoutE8s\(cost\)/);
  assert.match(backend, /Do not write game creator royalties here/);
});

check('docs capture Phase 1 invariant and Phase 2 bucket split path', () => {
  assert.match(docs, /1 ICP = 100 Tokens/);
  assert.match(docs, /1 ICP = 1,000 Tickets/);
  assert.match(docs, /1 Ticket = 100,000 e8s/);
  assert.match(docs, /100 tickets => 10,000,000 e8s/);
  assert.match(docs, /1000 tickets => 100,000,000 e8s/);
  assert.match(docs, /Phase 2[\s\S]*game creator earnings[\s\S]*NFT seller earnings[\s\S]*refunds/i);
});

const failures = [];
for (const [name, fn] of checks) {
  try {
    fn();
  } catch (error) {
    failures.push(`${name}: ${error.message}`);
  }
}

if (failures.length > 0) {
  console.error(`Payout Phase 1 accounting invariant validation FAILED (${checks.length - failures.length}/${checks.length})`);
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}

console.log(`Payout Phase 1 accounting invariant validation PASSED (${checks.length}/${checks.length})`);
for (const [name] of checks) console.log(`PASS ${name}`);
