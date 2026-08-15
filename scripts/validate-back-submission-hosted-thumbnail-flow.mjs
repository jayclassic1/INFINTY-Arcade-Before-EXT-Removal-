import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const index = readFileSync(join(root, 'index.html'), 'utf8');

const backMarkup = snippetAround("id='backSubThumbFile'", 700);
assert.ok(
  /onchange='handleSubmissionThumbUpload\(this,"backSubThumb"\)'/.test(backMarkup),
  'Back thumbnail file input must use the submission thumbnail upload helper'
);

const submissionUploadBody = functionBody('handleSubmissionThumbUpload');
assert.ok(
  submissionUploadBody.includes('uploadImageFileToGameAssets'),
  'submission thumbnail helper must upload to hosted game assets before setting hidden thumbnail value'
);
assert.ok(
  submissionUploadBody.includes('hosted-submission-thumbnail'),
  'submission thumbnail helper must use a dedicated hosted submission thumbnail scope'
);
assert.ok(
  /target\.value\s*=\s*url|target\)\s*target\.value\s*=\s*url/.test(submissionUploadBody),
  'hidden submission thumbnail value must be the hosted URL returned from uploadImageFileToGameAssets'
);
assert.ok(
  !/target\.value\s*=\s*dataUrl/.test(submissionUploadBody),
  'hidden submission thumbnail value must not be a base64 data URL'
);
assert.ok(
  !/await\s+optimizeThumbnailFile\(file\)/.test(submissionUploadBody),
  'submission thumbnail helper must not store optimized data URLs for backend submission'
);
assert.ok(
  /createObjectURL\(file\)/.test(submissionUploadBody),
  'submission thumbnail helper should keep a local preview while hosted upload is pending'
);
assert.ok(
  /revokeObjectURL/.test(submissionUploadBody),
  'submission thumbnail helper must revoke local object preview URLs after hosted upload settles'
);

const submitPayloadBody = functionBody('submitGamePayload');
assert.ok(
  submitPayloadBody.includes('assertSafeHostedThumbnailForSubmission'),
  'token submission path must guard unsafe thumbnail payloads before confirmation/payment'
);
assert.ok(
  submitPayloadBody.indexOf('assertSafeHostedThumbnailForSubmission') < submitPayloadBody.indexOf('arcadeConfirm'),
  'token submission thumbnail guard must run before fee confirmation/payment'
);
assert.ok(
  submitPayloadBody.indexOf('assertSafeHostedThumbnailForSubmission') < submitPayloadBody.indexOf('getBackendActor(true)'),
  'token submission thumbnail guard must run before backend submit call'
);

const backSubmitBody = functionBody('submitBackGame');
assert.ok(
  backSubmitBody.includes('assertSafeHostedThumbnailForSubmission'),
  'Back ICP payment path must guard unsafe thumbnail payloads before charge/submit'
);
assert.ok(
  backSubmitBody.indexOf('assertSafeHostedThumbnailForSubmission') < backSubmitBody.indexOf('getBackendActor(true)'),
  'Back ICP payment thumbnail guard must run before backend submitGameWithPayment call'
);

const guardBody = functionBody('assertSafeHostedThumbnailForSubmission');
assert.ok(guardBody.includes('data:image'), 'thumbnail guard must specifically detect data:image payloads');
assert.ok(/throw new Error/.test(guardBody), 'thumbnail guard must block unsafe thumbnail payloads');
assert.ok(/could not be hosted|contact admin/i.test(guardBody), 'thumbnail guard must provide user-safe hosted-upload failure copy');

console.log('Back submission hosted thumbnail flow validator passed');

function snippetAround(token, radius) {
  const at = index.indexOf(token);
  assert.notEqual(at, -1, `missing token ${token}`);
  return index.slice(Math.max(0, at - radius), Math.min(index.length, at + radius));
}

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
