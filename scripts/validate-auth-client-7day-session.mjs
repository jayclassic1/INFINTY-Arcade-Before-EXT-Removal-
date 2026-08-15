import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const indexPath = resolve(root, 'index.html');
const index = readFileSync(indexPath, 'utf8');

const checks = [];
const ok = (name, pass, detail = '') => checks.push({ name, pass, detail });

ok(
  'shared 7-day Internet Identity delegation TTL constant exists',
  /const\s+AUTH_SESSION_TTL_NS\s*=\s*BigInt\(\s*7\s*\*\s*24\s*\*\s*60\s*\*\s*60\s*\)\s*\*\s*1000000000n\s*;/.test(index),
  'Expected const AUTH_SESSION_TTL_NS = BigInt(7*24*60*60)*1000000000n;'
);

ok(
  'shared 7-day auth-client idle timeout constant exists',
  /const\s+AUTH_IDLE_TIMEOUT_MS\s*=\s*7\s*\*\s*24\s*\*\s*60\s*\*\s*60\s*\*\s*1000\s*;/.test(index),
  'Expected const AUTH_IDLE_TIMEOUT_MS = 7*24*60*60*1000;'
);

ok(
  'shared AuthClient.create options wire idleOptions.idleTimeout to 7 days',
  /const\s+AUTH_CLIENT_CREATE_OPTIONS\s*=\s*Object\.freeze\(\s*\{\s*idleOptions\s*:\s*Object\.freeze\(\s*\{\s*idleTimeout\s*:\s*AUTH_IDLE_TIMEOUT_MS\s*\}\s*\)\s*\}\s*\)\s*;/.test(index),
  'Expected AUTH_CLIENT_CREATE_OPTIONS to set idleOptions.idleTimeout: AUTH_IDLE_TIMEOUT_MS.'
);

const createCalls = [...index.matchAll(/AuthClient\.create\s*\(([^)]*)\)/g)].map((match) => match[1].trim());
ok(
  'all AuthClient.create calls use shared 7-day create options',
  createCalls.length > 0 && createCalls.every((args) => args === 'AUTH_CLIENT_CREATE_OPTIONS'),
  `Found AuthClient.create args: ${createCalls.map((args) => args || '<empty>').join(', ')}`
);

ok(
  'authClient.login uses shared 7-day maxTimeToLive constant',
  /authClient\.login\s*\(\s*\{[\s\S]*?maxTimeToLive\s*:\s*AUTH_SESSION_TTL_NS[\s\S]*?\}\s*\)/.test(index),
  'Expected login options to include maxTimeToLive: AUTH_SESSION_TTL_NS.'
);

ok(
  'default idle logout callback is not disabled',
  !/disableDefaultIdleCallback\s*:\s*true/.test(index),
  'disableDefaultIdleCallback: true was found; this task should preserve default idle safety behavior.'
);

const failures = checks.filter((check) => !check.pass);
for (const check of checks) {
  console.log(`${check.pass ? 'PASS' : 'FAIL'} ${check.name}${check.pass ? '' : ` — ${check.detail}`}`);
}

if (failures.length) {
  console.error(`\n${failures.length}/${checks.length} auth-client 7-day session checks failed.`);
  process.exit(1);
}

console.log(`\n${checks.length}/${checks.length} auth-client 7-day session checks passed.`);
