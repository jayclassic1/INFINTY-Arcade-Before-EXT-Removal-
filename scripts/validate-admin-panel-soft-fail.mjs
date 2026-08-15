import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const indexPath = join(root, 'index.html');
const index = readFileSync(indexPath, 'utf8');
const publishTest = readFileSync(join(root, 'scripts', 'test-frontend-publish.mjs'), 'utf8');

assert.ok(index.includes('function backendMethodAvailable('), 'missing backendMethodAvailable helper');
assert.ok(index.includes('function renderBackendSlicePending('), 'missing calm backend-missing message helper');
assert.ok(index.includes('TREASURY_BACKEND_PENDING_COPY'), 'missing shared treasury pending copy');

const loadTreasuryInfo = functionBody('loadTreasuryInfo');
assert.ok(loadTreasuryInfo.includes("backendMethodAvailable(be,'getTreasuryBalance')"), 'loadTreasuryInfo must guard getTreasuryBalance before calling it');
assert.ok(loadTreasuryInfo.includes('renderBackendSlicePending'), 'loadTreasuryInfo must render calm pending copy when treasury backend is absent');
assert.ok(!/Error:\s*'\s*\+\s*e\.message/.test(loadTreasuryInfo), 'loadTreasuryInfo must not dump raw e.message into treasury card');

const fillMax = functionBody('fillMaxTreasuryWithdraw');
assert.ok(fillMax.includes("backendMethodAvailable(be,'getTreasuryBalance')"), 'fillMaxTreasuryWithdraw must guard getTreasuryBalance');
assert.ok(!/Failed:\s*'\s*\+\s*\(e\.message\|\|e\)/.test(fillMax), 'fillMaxTreasuryWithdraw must not dump raw e.message');

const sweep = functionBody('adminSweepMainToOperating');
assert.ok(sweep.includes("backendMethodAvailable(be,'adminSweepMainToOperating')"), 'adminSweepMainToOperating must guard missing sweep update method');
assert.ok(!/\+\s*\(e\.message\|\|e\)\s*\+/.test(sweep), 'adminSweepMainToOperating must not dump raw thrown errors');

const withdraw = functionBody('adminWithdrawTreasury');
assert.ok(withdraw.includes("backendMethodAvailable(be,'adminWithdrawToAccountId')"), 'adminWithdrawTreasury must guard account-id withdrawal method');
assert.ok(withdraw.includes("backendMethodAvailable(be,'adminWithdrawTreasury')"), 'adminWithdrawTreasury must guard principal withdrawal method');
assert.ok(!/\+\s*e\.message\s*\+/.test(withdraw), 'adminWithdrawTreasury must not dump raw e.message');

const stats = functionBody('loadTreasuryStats');
assert.ok(stats.includes("backendMethodAvailable(be2,'getTreasuryBalance')"), 'loadTreasuryStats must guard optional getTreasuryBalance');
assert.ok(stats.includes('Treasury backend pending') || stats.includes('Pending backend'), 'loadTreasuryStats should show calm pending copy');

const ticketFunding = functionBody('loadTicketReserveFundingAdmin');
assert.ok(ticketFunding.includes("backendMethodAvailable(be,'adminGetAllGames')"), 'loadTicketReserveFundingAdmin must guard missing adminGetAllGames');
assert.ok(ticketFunding.includes('Ticket reserve funding audit is disabled'), 'ticket reserve funding should show calm pending copy');
assert.ok(!/Failed:\s*'\s*\+\s*\(e\.message\|\|e\)/.test(ticketFunding), 'loadTicketReserveFundingAdmin must not dump raw backend errors');

const gameAdminList = functionBody('renderGameAdminList');
assert.ok(gameAdminList.includes("backendMethodAvailable(be,'adminGetAllGames')"), 'renderGameAdminList must guard missing adminGetAllGames');
assert.ok(!/Failed to load games:\s*'\s*\+\s*\(e\.message\|\|e\)/.test(gameAdminList), 'renderGameAdminList must not dump raw backend errors');

assert.ok(index.includes('function safeUploadErrorMessage('), 'missing shared safeUploadErrorMessage helper');
assert.ok(index.includes('function showUploadError('), 'missing shared showUploadError helper');
for (const name of ['handleSubmissionThumbUpload','handleHostedThumbnailUpload','handleGameScreenshotUploads','handleForumImageUpload','submitForumPost','submitReply','submitNftUpload','submitProposal']) {
  const body = functionBody(name);
  assert.ok(!/(alert|innerHTML)\([^;]*(e\.message|\(e\.message\|\|e\)|String\(e\))/s.test(body), `${name} must not display raw upload/backend errors`);
}
assert.ok(functionBody('submitProposal').includes('safeUploadErrorMessage'), 'submitProposal must sanitize image/backend upload errors');
assert.ok(functionBody('submitForumPost').includes('safeUploadErrorMessage'), 'submitForumPost must sanitize local image storage errors');
assert.ok(functionBody('submitReply').includes('safeUploadErrorMessage'), 'submitReply must sanitize local image storage errors');

assert.ok(publishTest.includes("'index.html'") || publishTest.includes('"index.html"'), 'sanitized frontend publish test must still assert index.html is included');

console.log('admin panel soft-fail validator passed');

function functionBody(name) {
  let start = index.indexOf(`async function ${name}(`);
  if (start === -1) start = index.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `missing function ${name}`);
  const brace = index.indexOf('{', start);
  assert.notEqual(brace, -1, `missing opening brace for ${name}`);
  let depth = 0;
  for (let i = brace; i < index.length; i += 1) {
    const ch = index[i];
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return index.slice(brace + 1, i);
    }
  }
  throw new Error(`unterminated function ${name}`);
}
