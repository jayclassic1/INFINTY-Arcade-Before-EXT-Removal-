import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const modulePath = new URL('./prepare-index-only-deploy.mjs', import.meta.url);
const deployScript = join(root, 'scripts', 'deploy-index-only.ps1');

const tempRoot = mkdtempSync(join(tmpdir(), 'ia-index-only-test-'));

try {
  const fixtureIndex = join(tempRoot, '.deploy', 'frontend-public', 'index.html');
  mkdirSync(join(tempRoot, '.deploy', 'frontend-public'), { recursive: true });
  const html = '<!doctype html><html><head><title>Infinity</title></head><body>ok</body></html>\n';
  writeFileSync(fixtureIndex, html, 'utf8');

  const mod = await import(modulePath.href);

  assert.equal(mod.FRONTEND_CANISTER, 'mprew-viaaa-aaaah-quola-cai');
  assert.throws(() => mod.assertExpectedRoot(join(tempRoot, 'wrong-root')), /Refusing non-canonical root/);
  assert.throws(() => mod.assertFrontendCanister('ewgfh-vqaaa-aaaah-qtixa-cai'), /Refusing frontend canister/);

  const artifacts = mod.prepareIndexOnlyDeploy({
    rootDir: tempRoot,
    writeArgs: true,
    outDir: join(tempRoot, '.deploy', 'index-only'),
  });

  assert.equal(artifacts.key, '/index.html');
  assert.equal(artifacts.canister, 'mprew-viaaa-aaaah-quola-cai');
  assert.equal(artifacts.identity.sha256, createHash('sha256').update(Buffer.from(html)).digest('hex'));
  assert.equal(artifacts.gzip.sha256, createHash('sha256').update(gzipSync(Buffer.from(html), { level: 9 })).digest('hex'));
  assert.ok(existsSync(artifacts.identity.argFile), 'identity arg file should be written');
  assert.ok(existsSync(artifacts.gzip.argFile), 'gzip arg file should be written');

  const identityArg = readFileSync(artifacts.identity.argFile, 'utf8');
  const gzipArg = readFileSync(artifacts.gzip.argFile, 'utf8');
  assert.match(identityArg, /key\s*=\s*"\/index\.html"/);
  assert.match(identityArg, /content_encoding\s*=\s*"identity"/);
  assert.match(gzipArg, /key\s*=\s*"\/index\.html"/);
  assert.match(gzipArg, /content_encoding\s*=\s*"gzip"/);
  assert.doesNotMatch(`${identityArg}\n${gzipArg}`, /ewgfh-vqaaa-aaaah-qtixa-cai/);

  const liveFixture = join(tempRoot, 'live-index.html');
  writeFileSync(liveFixture, html, 'utf8');
  assert.equal(mod.verifyLiveIndexSha(readFileSync(liveFixture), artifacts.identity.sha256), true);
  assert.equal(mod.verifyLiveIndexSha(Buffer.from('different'), artifacts.identity.sha256), false);

  const check = spawnSync(process.execPath, ['scripts/prepare-index-only-deploy.mjs', '--check', '--no-build'], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.equal(check.status, 0, `--check failed\nSTDOUT:\n${check.stdout}\nSTDERR:\n${check.stderr}`);
  assert.match(check.stdout, new RegExp(`${['i', 'cp'].join('')} canister call mprew-viaaa-aaaah-quola-cai store`));
  assert.match(check.stdout, /identity/);
  assert.match(check.stdout, /gzip/);
  assert.doesNotMatch(check.stdout + check.stderr, /ewgfh-vqaaa-aaaah-qtixa-cai/);

  const ps = readFileSync(deployScript, 'utf8');
  assert.match(ps, /build-frontend-publish\.mjs/);
  assert.match(ps, /predeploy-check\.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai/);
  assert.match(ps, /npm run deploy:guard/);
  assert.match(ps, /-Deploy/);
  assert.match(ps, /'Accept-Encoding' = 'identity'/);
  assert.match(ps, new RegExp(`run-icp-tool\\.mjs ${['i', 'cp'].join('')} canister call`));
  assert.doesNotMatch(ps, /ewgfh-vqaaa-aaaah-qtixa-cai/);
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}

console.log('index-only deploy hardening tests passed');
