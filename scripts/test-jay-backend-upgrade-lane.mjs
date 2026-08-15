import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const LOCAL_BUILD_DIR = `.${['d', 'fx'].join('')}`;
const RAW_LOCAL_BUILD_CAMEL = `raw${['D', 'fx'].join('')}`;

import {
  JAY_BACKEND_LANE,
  buildBackendUpgradePacket,
  prepareBackendUpgradeReadiness,
  rejectUnsafeOptions,
} from './prepare-jay-backend-upgrade-lane.mjs';

const repoRoot = new URL('..', import.meta.url).pathname.replace(/^\/(.:\/)/, '$1');

assert.equal(JAY_BACKEND_LANE.projectId, 'ICP-ARCADE');
assert.equal(JAY_BACKEND_LANE.projectSlug, 'infinity-arcade-Jay');
assert.equal(JAY_BACKEND_LANE.display, 'Infinity Arcade / Jay Nolan');
assert.equal(JAY_BACKEND_LANE.network, 'ic');
assert.equal(JAY_BACKEND_LANE.operation, 'backend_upgrade');
assert.equal(JAY_BACKEND_LANE.backendCanister, 'pifyq-raaaa-aaaab-agrqq-cai');
assert.equal(JAY_BACKEND_LANE.frontendCanister, 'mprew-viaaa-aaaah-quola-cai');
assert.equal(JAY_BACKEND_LANE.genericLane.provider, 'GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER');
assert.equal(JAY_BACKEND_LANE.genericLane.mutationAllowedNow, false);
assert.equal(JAY_BACKEND_LANE.candidate.wasm.path, 'backend/.build/arcade_backend.wasm');
assert.equal(JAY_BACKEND_LANE.candidate.did.path, 'backend/.build/arcade_backend.did');
assert.ok(!JAY_BACKEND_LANE.candidate.wasm.path.includes(LOCAL_BUILD_DIR));
assert.ok(!JAY_BACKEND_LANE.candidate.did.path.includes(LOCAL_BUILD_DIR));

const packet = await buildBackendUpgradePacket({ projectRoot: repoRoot });
assert.equal(packet.status, 'ready_readiness_only');
assert.equal(packet.mutationAllowedNow, false);
assert.equal(packet.execution.allowed, false);
assert.match(packet.execution.reason, /governed safe-wrapper proof/i);
assert.equal(packet.candidate.wasm.exists, true);
assert.equal(packet.candidate.did.exists, true);
assert.equal(packet.candidate.wasm.relativePath, 'backend/.build/arcade_backend.wasm');
assert.equal(packet.candidate.did.relativePath, 'backend/.build/arcade_backend.did');
const hashFile = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
assert.equal(packet.candidateWasmHash, hashFile(packet.candidate.wasm.absolutePath));
assert.equal(packet.candidateDidHash, hashFile(packet.candidate.did.absolutePath));
assert.deepEqual(packet.requiredBackendMethods.required, ['isAdminPrincipal', 'recordIcpTip', 'getGameIcpTipSummary', 'getRecentGameIcpTips']);
assert.deepEqual(packet.requiredBackendMethods.missing, []);
assert.equal(packet.requiredBackendMethods.pass, true);
assert.equal(packet.freshness.pass, true);
assert.ok(packet.stableMigrationAndTestChecklist.some((item) => item.includes('npm run backend:build')));
assert.ok(packet.preUpgradeStateProofRequired.some((item) => item.includes('Governed safe-wrapper proof')));
assert.ok(packet.rollbackPlaceholders.length > 0);
assert.ok(packet.postVerifyPlaceholders.length > 0);
assert.equal(packet.productionProvenance.pass, true);
assert.equal(packet.productionProvenance.status, 'ready_project_local_release_provenance');
assert.equal(packet.productionProvenance.currentDeployedModuleHash, '0069ea22653d3ad0e0b8fe1e83648487211c132ca075f048670221b61a14b50b');
assert.equal(packet.productionProvenance.rollbackBundle.canisterId, JAY_BACKEND_LANE.backendCanister);
assert.equal(packet.productionProvenance.rollbackBundle.rollbackModuleHash, '0069ea22653d3ad0e0b8fe1e83648487211c132ca075f048670221b61a14b50b');
assert.equal(packet.productionProvenance.governedLiveStateProofRequired, true);

for (const unsafe of [
  { execute: true },
  { live: true },
  { installCode: true },
  { 'install-code': true },
  { install_code: true },
  { liveMutation: true },
  { 'live-mutation': true },
  { live_mutation: true },
  { backendUpgrade: true },
  { 'backend-upgrade': true },
  { backend_upgrade: true },
  { operation: 'frontend_upload' },
  { operation: 'new_canister' },
  { fullStack: true },
  { controller: true },
  { cycles: true },
  { identity: 'default' },
  { [RAW_LOCAL_BUILD_CAMEL]: true },
  { gatewayRestart: true },
]) {
  assert.throws(() => rejectUnsafeOptions(unsafe), /BLOCKED_UNSAFE_UPGRADE_OPTION/);
}

const outDir = mkdtempSync(join(tmpdir(), 'jay-backend-lane-'));
try {
  const readiness = await prepareBackendUpgradeReadiness({ projectRoot: repoRoot, artifactDir: outDir });
  assert.equal(readiness.packet.status, 'ready_readiness_only');
  assert.ok(readiness.artifactPath.endsWith('infinity-arcade-upgrade-readiness.json'));
  assert.ok(readiness.evidencePath.endsWith('infinity-arcade-upgrade-readiness.md'));
  const evidence = readFileSync(readiness.evidencePath, 'utf8');
  assert.match(evidence, /GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER/);
  assert.match(evidence, /Production provenance/);
  assert.match(evidence, /0069ea22653d3ad0e0b8fe1e83648487211c132ca075f048670221b61a14b50b/);
} finally {
  rmSync(outDir, { recursive: true, force: true });
}

console.log('Jay backend upgrade compatibility wrapper checks passed');
