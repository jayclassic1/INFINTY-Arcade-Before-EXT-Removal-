import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const runTool = join(root, 'scripts', 'run-icp-tool.mjs');

const expectedIdentity = 'mcp-identity';
const expectedPrincipal = '7uj7m-2tv5i-shpmb-wy5hq-2fndc-ph5cx-gvqx3-uccl3-zf3nb-q4ata-vae';
const backendCanister = 'pifyq-raaaa-aaaab-agrqq-cai';
const frontendCanister = 'mprew-viaaa-aaaah-quola-cai';
const passwordFileWin = process.env.ICP_IDENTITY_PASSWORD_FILE
  ?? 'C:\\Users\\Jesse\\.openclaw\\secrets\\icp-cli\\mcp-identity.password';

function toWslPath(winPath) {
  const match = String(winPath).match(/^([A-Za-z]):\\(.*)$/);
  if (!match) return winPath;
  return `/mnt/${match[1].toLowerCase()}/${match[2].replace(/\\/g, '/')}`;
}

const passwordFile = toWslPath(passwordFileWin);

function fail(message) {
  console.error(`ICP deploy identity guard failed: ${message}`);
  process.exit(1);
}

function run(args, options = {}) {
  const result = spawnSync(process.execPath, [runTool, 'icp', ...args], {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.status !== 0) {
    if (!options.quiet) process.stderr.write(result.stderr || result.stdout || '');
    fail(`${args.join(' ')} exited with ${result.status}`);
  }
  return result.stdout.trim();
}

function wslRead(command) {
  const result = spawnSync('wsl.exe', ['bash', '-lc', command], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout || '');
    fail(`WSL inspection failed: ${command}`);
  }
  return result.stdout.trim();
}

if (!existsSync(passwordFileWin)) {
  fail(`identity password file missing: ${passwordFileWin}`);
}

const identityList = JSON.parse(run(['identity', 'list', '--json', '--identity-password-file', passwordFile]));
if (identityList.default_identity !== expectedIdentity) {
  fail(`default identity is ${identityList.default_identity}; expected ${expectedIdentity}`);
}

const identity = identityList.identities.find((entry) => entry.name === expectedIdentity);
if (!identity) fail(`${expectedIdentity} is missing from icp identity list`);
if (identity.principal !== expectedPrincipal) {
  fail(`${expectedIdentity} principal is ${identity.principal}; expected ${expectedPrincipal}`);
}
if (identityList.default_identity === 'anonymous' || identity.principal === '2vxsx-fae') {
  fail('anonymous identity is selected for deploy');
}

const currentDefault = run(['identity', 'default', '--identity-password-file', passwordFile]);
if (currentDefault !== expectedIdentity) fail(`identity default returned ${currentDefault}`);

const principal = run(['identity', 'principal', '--identity', expectedIdentity, '--identity-password-file', passwordFile]);
if (principal !== expectedPrincipal) fail(`identity principal returned ${principal}`);

const identityStore = JSON.parse(wslRead('cat ~/.local/share/icp-cli/identity/identity_list.json'));
const stored = identityStore.identities?.[expectedIdentity];
if (!stored) fail(`${expectedIdentity} missing from WSL identity store`);
if (stored.kind !== 'pem' || stored.format !== 'pbes2') {
  fail(`${expectedIdentity} must use encrypted password storage (kind=pem, format=pbes2); got kind=${stored.kind}, format=${stored.format}`);
}

const pemHeader = wslRead(`head -1 ~/.local/share/icp-cli/identity/keys/${expectedIdentity}.pem`);
if (pemHeader !== '-----BEGIN ENCRYPTED PRIVATE KEY-----') {
  fail(`${expectedIdentity} key is not encrypted in WSL identity storage`);
}

for (const canister of [backendCanister, frontendCanister]) {
  const status = JSON.parse(run([
    'canister', 'status', canister,
    '--network', 'ic',
    '--public',
    '--json',
    '--identity-password-file', passwordFile,
  ]));
  if (!Array.isArray(status.controllers) || !status.controllers.includes(expectedPrincipal)) {
    fail(`${expectedPrincipal} is not a controller on ${canister}`);
  }
}

console.log(`ICP deploy identity guard passed: ${expectedIdentity} -> ${expectedPrincipal}; encrypted password storage verified; controller on ${backendCanister} and ${frontendCanister}.`);
