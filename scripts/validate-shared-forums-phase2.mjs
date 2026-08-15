import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const backend = fs.readFileSync(path.join(root, 'backend', 'main.mo'), 'utf8');
const frontend = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));

const failures = [];
const assert = (condition, message) => { if (!condition) failures.push(message); };
const hasBackendMethod = (name) => new RegExp(`public\\s+(?:(?:shared(?:\\s+query)?(?:\\s*\\([^)]*\\))?)|query)\\s+func\\s+${name}\\s*\\(`).test(backend);
const hasFrontendIdl = (name) => new RegExp(`${name}\\s*:\\s*IDL\\.Func`).test(frontend);

const backendMethods = [
  'createForumThread',
  'getForumThreads',
  'addForumReply',
  'createProposal',
  'castVote',
  'getProposals',
  'getProposal',
  'daoStats',
  'getVotingPower',
  'getGamerBadges',
];
for (const name of backendMethods) assert(hasBackendMethod(name), `backend missing ${name}`);

const idlMethods = [
  'createForumThread',
  'getForumThreads',
  'addForumReply',
  'getProposals',
  'getProposal',
  'daoStats',
  'getVotingPower',
  'getGamerBadges',
];
for (const name of idlMethods) assert(hasFrontendIdl(name), `frontend IDL missing ${name}`);

assert(/async\s+function\s+fetchForumPostsFromBackend\s*\(/.test(frontend), 'frontend missing shared forum fetch helper');
assert(/async\s+function\s+createForumThreadOnBackend\s*\(/.test(frontend), 'frontend missing shared forum thread create helper');
assert(/async\s+function\s+addForumReplyOnBackend\s*\(/.test(frontend), 'frontend missing shared forum reply helper');
assert(/backendMethodAvailable\(be\s*,\s*['"]getForumThreads['"]\)/.test(frontend), 'frontend does not guard backend forum method availability');
assert(/daoStats\s*:\s*IDL\.Func\(\[\],\[IDL\.Record\(\{proposals:IDL\.Nat,activeProposals:IDL\.Nat,badgeHolders:IDL\.Nat,forumThreads:IDL\.Nat\}\)\]/.test(frontend), 'frontend daoStats IDL does not match backend DaoStats shape');
assert(/Number\(stats\.proposals\)/.test(frontend) && /Number\(stats\.badgeHolders\)/.test(frontend), 'frontend DAO dashboard does not read backend DaoStats field names');
assert(/public\s+shared\s+query\s*\(msg\)\s+func\s+getForumThreads/.test(backend), 'backend getForumThreads must be caller-aware for DAO visibility');
assert(/isDaoSection\(section\)\s+and\s+not\s+hasDaoAccess\(msg\.caller\)\)\s+return\s+\[\]/.test(backend), 'backend getForumThreads must gate DAO sections by caller access');
assert(/getBackendActor\(isDaoForumSection\(section\)\)/.test(frontend), 'frontend must use authenticated actor for DAO forum reads');
assert(/getLocalForumPosts\s*\(/.test(frontend) && /saveLocalForumPosts\s*\(/.test(frontend), 'frontend fallback local forum helpers not preserved');
assert(!/function\s+getForumPosts\s*\([^)]*\)\s*{\s*try\s*{\s*return\s+JSON\.parse\(localStorage\.getItem\('forum_/.test(frontend), 'legacy getForumPosts is still localStorage-only');

// Phase 3: local-only forum media/cycle policy guardrails.
assert(/FORUM_TITLE_MAX_CHARS\s*:\s*Nat\s*=\s*120/.test(backend), 'backend missing forum title cap');
assert(/FORUM_BODY_MAX_CHARS\s*:\s*Nat\s*=\s*4_000/.test(backend), 'backend missing forum body cap');
assert(/FORUM_REPLY_BODY_MAX_CHARS\s*:\s*Nat\s*=\s*2_000/.test(backend), 'backend missing forum reply body cap');
assert(/FORUM_AUTHOR_MAX_CHARS\s*:\s*Nat\s*=\s*80/.test(backend), 'backend missing forum author cap');
assert(/FORUM_IMAGE_REF_MAX_CHARS\s*:\s*Nat\s*=\s*512/.test(backend), 'backend missing compact forum image reference cap');
assert(/func\s+hasForumMediaAccess\s*\(owner\s*:\s*Principal\)/.test(backend), 'backend missing forum media eligibility helper');
assert(/isAdmin\(owner\)\s+or\s+votingPowerOf\(owner\)\s*>\s*0\s+or\s+hasContributorBadge\(owner\)/.test(backend), 'backend media eligibility must allow admin, voting power, or contributor badges');
assert(/func\s+validateForumImage\s*\(caller\s*:\s*Principal\s*,\s*image\s*:\s*\?Text\)/.test(backend), 'backend missing forum image validator');
assert(/Forum image posting requires Voting Power, contributor badge, or admin access/.test(backend), 'backend missing media eligibility rejection');
assert(/Inline\/base64 forum images are not allowed/.test(backend), 'backend must reject inline/base64 forum images');
assert(/Forum image must be an http\(s\), ipfs, arweave, or asset reference/.test(backend), 'backend must restrict forum image reference schemes');
assert(/let normalizedImage = switch \(validateForumImage\(msg\.caller, image\)\)/.test(backend), 'backend create/reply paths must normalize forum images');
assert(/Body required for text-first forum posting/.test(backend), 'backend must keep forum threads text-first');
assert(/Reply body required for text-first forum posting/.test(backend), 'backend must keep forum replies text-first');

assert(/async\s+function\s+getForumMediaEligibility\s*\(/.test(frontend), 'frontend missing forum media eligibility helper');
assert(/async\s+function\s+ensureForumImageAllowed\s*\(/.test(frontend), 'frontend missing client-side forum image policy gate');
assert(/function\s+validateForumImageRef\s*\(/.test(frontend), 'frontend missing compact image reference validator');
assert(/Inline\/base64 images are not allowed for forum posts/.test(frontend), 'frontend must block inline/base64 forum images');
assert(/forum-image-action/.test(frontend) && /forum-image-policy-msg/.test(frontend), 'frontend missing forum media controls/policy message');
assert(/addForumImageReference\(/.test(frontend), 'frontend should collect compact image refs instead of inline uploads');
assert(/handleForumImageUpload\s*\([\s\S]*?alert\(forumImagePolicyMessage\(\)\);[\s\S]*?return;/.test(frontend), 'legacy forum file uploader must be blocked for new posts');
assert(/const allowedImage=await ensureForumImageAllowed\(imageData\)/.test(frontend), 'frontend thread submit must gate image refs');
assert(/const allowedImage=await ensureForumImageAllowed\(replyImage\)/.test(frontend), 'frontend reply submit must gate image refs');
assert(pkg.scripts?.['validate:forum-media-policy'] === 'node scripts/validate-shared-forums-phase2.mjs', 'package script validate:forum-media-policy missing');

const forbiddenDeployTool = String.fromCharCode(100, 102, 120);
const forbiddenDeployToolRe = new RegExp(`\\b${forbiddenDeployTool}\\b`, 'i');
assert(!forbiddenDeployToolRe.test(backend), 'backend source must not introduce raw deploy-tool references');
assert(!forbiddenDeployToolRe.test(frontend), 'frontend source must not introduce raw deploy-tool references');
assert(!forbiddenDeployToolRe.test(fs.readFileSync(import.meta.filename, 'utf8')), 'validator must not introduce raw deploy-tool command text');
assert(pkg.scripts?.['validate:shared-forums-phase2'] === 'node scripts/validate-shared-forums-phase2.mjs', 'package script validate:shared-forums-phase2 missing');

if (failures.length) {
  console.error(`Shared forums/proposals phase2 validation failed (${failures.length}):`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log('Shared forums/proposals phase2 validation passed');
