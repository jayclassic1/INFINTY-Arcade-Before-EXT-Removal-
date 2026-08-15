#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const frontendPath = path.join(root, 'index.html');
const frontend = fs.readFileSync(frontendPath, 'utf8');

const failures = [];
const passes = [];

function test(name, predicate, detail) {
  try {
    if (predicate()) passes.push(name);
    else failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
  } catch (error) {
    failures.push(`${name} — threw ${error.message}`);
  }
}

function has(pattern) {
  return pattern.test(frontend);
}

function lacks(pattern) {
  return !pattern.test(frontend);
}

const royaltySectionStart = frontend.indexOf('<!-- ====== ROYALTIES DASHBOARD ====== -->');
const royaltySectionEnd = frontend.indexOf('<!-- ====== DAO PUBLIC DASHBOARD ====== -->', royaltySectionStart);
const royaltySection = royaltySectionStart === -1 || royaltySectionEnd === -1
  ? ''
  : frontend.slice(royaltySectionStart, royaltySectionEnd);

function sectionHas(pattern) {
  return pattern.test(royaltySection);
}

function sectionLacks(pattern) {
  return !pattern.test(royaltySection);
}

test('royalties dashboard exists', () => royaltySection.length > 0);
test('manual claim copy exists without future-phase wording', () =>
  sectionHas(/manual(?:ly)?\s+claim/i)
  && sectionHas(/claim(?:ing)?\s+is\s+manual/i)
  && sectionLacks(/manual claim[^.\n]{0,120}Phase 2|claim path[^.\n]{0,120}hardened in Phase 2/i),
  'dashboard must explain manual claims as current user guidance, not a future implementation phase');
test('claimable creator/seller earnings are labeled as ICP e8s', () =>
  sectionHas(/Creator\s*\/\s*Seller Earnings/i)
  && sectionHas(/ICP e8s claimable earnings/i)
  && sectionHas(/Creator earnings \/ royalties/i)
  && sectionHas(/Artist \/ seller earnings/i));
test('refund wording is separate from creator and seller earnings', () =>
  sectionHas(/separate ICP refunds/i)
  && sectionHas(/same (?:safe manual )?claim (?:action|flow)/i)
  && sectionHas(/Creator and seller buckets stay separate in accounting/i)
  && sectionLacks(/refunds?[^.\n]{0,80}(?:creator earnings|royalties)/i));
test('Tokens and Tickets closed-loop copy exists', () =>
  has(/Tokens are arcade credits only/i)
  && has(/Tickets are prize\/perk points only/i)
  && has(/Tickets cannot be exchanged for ICP/i));
test('responsible tax/no-advice copy exists', () =>
  has(/creators? are responsible for their own tax reporting/i)
  && has(/no tax advice/i));
test('no automatic weekly creator payout promise remains', () => lacks(/(?:creator|seller|royalt|earning)[^.\\n]{0,100}(automatic(?:ally)?|weekly|every week)|weekly[^.\\n]{0,100}(?:creator|seller|royalt|earning|payout|paid out)/i));
test('no ticket-to-ICP cashout language exists', () => lacks(/tickets?[^.\\n]{0,100}(?:can|may|able to|will|automatically)[^.\\n]{0,60}(?:cash\\s*out|cash-out|exchanged? for ICP|redeem(?:ed)? for ICP|cashout)/i));
test('category breakdown is labeled display-only/deferred rather than inventing unsupported values', () =>
  sectionHas(/category breakdown/i)
  && sectionHas(/display-only/i)
  && sectionHas(/do not estimate/i));

test('frontend text has no known mojibake markers from Windows encoding rewrites', () =>
  lacks(/A��|A\?\?|�\?\?|�O|�o\./i),
  'index.html must stay valid UTF-8 and must not contain known mojibake markers');

if (failures.length > 0) {
  console.error('Creator earnings Phase 4 validation FAILED');
  for (const failure of failures) console.error(`❌ ${failure}`);
  if (passes.length > 0) {
    console.error('\nPassed checks:');
    for (const pass of passes) console.error(`✅ ${pass}`);
  }
  process.exit(1);
}

console.log(`Creator earnings Phase 4 validation PASSED (${passes.length}/${passes.length})`);
for (const pass of passes) console.log(`✅ ${pass}`);

