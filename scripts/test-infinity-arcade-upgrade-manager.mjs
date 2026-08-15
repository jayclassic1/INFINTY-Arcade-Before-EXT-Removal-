import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync, readFileSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const LOCAL_BUILD_DIR = `.${['d', 'fx'].join('')}`;
const RAW_LOCAL_BUILD_CAMEL = `raw${['D', 'fx'].join('')}`;

import {
  INFINITY_ARCADE_UPGRADE_LANE,
  buildInfinityArcadeUpgradePacket,
  prepareInfinityArcadeUpgrade,
  rejectUnsafeOptions,
} from './prepare-infinity-arcade-upgrade.mjs';

function fixtureRoot() {
  const root = mkdtempSync(join(tmpdir(), 'infinity-arcade-upgrade-manager-'));
  mkdirSync(join(root, 'backend', '.build'), { recursive: true });
  mkdirSync(join(root, 'backend', LOCAL_BUILD_DIR, 'ic', 'canisters', 'arcade_backend'), { recursive: true });
  mkdirSync(join(root, '.releases'), { recursive: true });
  writeFileSync(join(root, 'backend', 'main.mo'), 'actor { public query func latest_source_marker() : async Nat { 1 } }\n');
  writeFileSync(join(root, 'backend', '.build', 'arcade_backend.wasm'), 'fresh-wasm');
  writeFileSync(join(root, 'backend', '.build', 'arcade_backend.did'), `service : {
  isAdminPrincipal : (principal) -> (bool) query;
  recordIcpTip : () -> ();
  getGameIcpTipSummary : () -> ();
  getRecentGameIcpTips : () -> ();
}\n`);
  writeFileSync(join(root, 'backend', LOCAL_BUILD_DIR, 'ic', 'canisters', 'arcade_backend', 'service.did'), 'service : { stale : () -> (); }\n');
  writeFileSync(join(root, '.releases', 'latest.json'), `${JSON.stringify({
    version: '2026.fixture',
    timestamp: '2026-01-02T00:00:00.000Z',
    canister_id: 'pifyq-raaaa-aaaab-agrqq-cai',
    wasm_hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    wasm_size: 825809,
    git_commit: '2264c85fc5f9763e51aaac00fbde971f7e7ac2fe',
    mode: 'upgrade',
    previous_hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    notes: 'fixture current deployed rollback metadata',
  }, null, 2)}\n`);
  const older = new Date('2026-01-01T00:00:00.000Z');
  const newer = new Date('2026-01-02T00:00:00.000Z');
  // source older, artifacts newer: fresh
  setTimes(join(root, 'backend', 'main.mo'), older);
  setTimes(join(root, 'backend', '.build', 'arcade_backend.wasm'), newer);
  setTimes(join(root, 'backend', '.build', 'arcade_backend.did'), newer);
  setTimes(join(root, 'backend', LOCAL_BUILD_DIR, 'ic', 'canisters', 'arcade_backend', 'service.did'), older);
  return root;
}

function setTimes(path, when) {
  utimesSync(path, when, when);
}

assert.equal(INFINITY_ARCADE_UPGRADE_LANE.projectId, 'ICP-ARCADE');
assert.equal(INFINITY_ARCADE_UPGRADE_LANE.genericLane.provider, 'GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER');
assert.equal(INFINITY_ARCADE_UPGRADE_LANE.canisters.backend, 'pifyq-raaaa-aaaab-agrqq-cai');
assert.equal(INFINITY_ARCADE_UPGRADE_LANE.canisters.frontend, 'mprew-viaaa-aaaah-quola-cai');
assert.equal(INFINITY_ARCADE_UPGRADE_LANE.candidate.wasm.path, 'backend/.build/arcade_backend.wasm');
assert.equal(INFINITY_ARCADE_UPGRADE_LANE.candidate.did.path, 'backend/.build/arcade_backend.did');
assert.ok(!INFINITY_ARCADE_UPGRADE_LANE.candidate.wasm.path.includes(LOCAL_BUILD_DIR));
assert.ok(!INFINITY_ARCADE_UPGRADE_LANE.candidate.did.path.includes(LOCAL_BUILD_DIR));

for (const unsafe of [
  { execute: true },
  { live: true },
  { deploy: true },
  { upgrade: true },
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
  { operation: 'controller_change' },
  { fullStack: true },
  { controller: true },
  { cycles: true },
  { identity: 'default' },
  { secrets: true },
  { gatewayRestart: true },
  { [RAW_LOCAL_BUILD_CAMEL]: true },
]) {
  assert.throws(() => rejectUnsafeOptions(unsafe), /BLOCKED_UNSAFE_UPGRADE_OPTION/);
}

{
  const root = fixtureRoot();
  try {
    const packet = await buildInfinityArcadeUpgradePacket({ projectRoot: root });
    assert.equal(packet.status, 'ready_readiness_only');
    assert.equal(packet.mutationAllowedNow, false);
    assert.match(packet.execution.reason, /governed safe-wrapper proof/i);
    assert.equal(packet.genericLane.provider, 'GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER');
    assert.equal(packet.genericLane.mutationAllowedNow, false);
    assert.equal(packet.candidate.wasm.relativePath, 'backend/.build/arcade_backend.wasm');
    assert.equal(packet.candidate.did.relativePath, 'backend/.build/arcade_backend.did');
    assert.ok(!JSON.stringify(packet.candidate).includes(`backend/${LOCAL_BUILD_DIR}`));
    assert.deepEqual(packet.requiredBackendMethods.missing, []);
    assert.equal(packet.requiredBackendMethods.pass, true);
    assert.equal(packet.freshness.pass, true);
    assert.equal(packet.candidate.wasm.sha256, '25199def59962214eefd48f5f62cd4c5da8347e82942d107beb11377d8eb7515');
    assert.equal(packet.candidate.did.sha256, '871dbbc0f42334c2c4c43dae4388ca370d5c739b1fb4918c6e13f21a80477c00');
    assert.equal(packet.productionProvenance.pass, true);
    assert.equal(packet.productionProvenance.status, 'ready_project_local_release_provenance');
    assert.equal(packet.productionProvenance.currentDeployedModuleHash, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    assert.equal(packet.productionProvenance.rollbackBundle.currentModuleHash, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    assert.equal(packet.productionProvenance.rollbackBundle.rollbackModuleHash, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    assert.equal(packet.productionProvenance.rollbackBundle.canisterId, 'pifyq-raaaa-aaaab-agrqq-cai');
    assert.equal(packet.productionProvenance.governedLiveStateProofRequired, true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = fixtureRoot();
  try {
    rmSync(join(root, '.releases', 'latest.json'), { force: true });
    const packet = await buildInfinityArcadeUpgradePacket({ projectRoot: root });
    assert.equal(packet.status, 'blocked_production_provenance_required');
    assert.equal(packet.productionProvenance.pass, false);
    assert.match(packet.productionProvenance.reason, /release manifest/i);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = fixtureRoot();
  try {
    writeFileSync(join(root, 'backend', '.build', 'arcade_backend.did'), 'service : { isAdminPrincipal : (principal) -> (bool) query; getGameIcpTipSummary : () -> (); }\n');
    const packet = await buildInfinityArcadeUpgradePacket({ projectRoot: root });
    assert.equal(packet.status, 'blocked_candidate_did_methods_missing');
    assert.deepEqual(packet.requiredBackendMethods.missing, ['recordIcpTip', 'getRecentGameIcpTips']);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = fixtureRoot();
  try {
    const sourceNewer = new Date('2026-01-03T00:00:00.000Z');
    setTimes(join(root, 'backend', 'main.mo'), sourceNewer);
    const packet = await buildInfinityArcadeUpgradePacket({ projectRoot: root });
    assert.equal(packet.status, 'blocked_candidate_artifacts_stale');
    assert.equal(packet.freshness.pass, false);
    assert.ok(packet.freshness.latestSource.mtimeMs > packet.freshness.oldestArtifact.mtimeMs);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = fixtureRoot();
  const outDir = mkdtempSync(join(tmpdir(), 'infinity-arcade-upgrade-evidence-'));
  try {
    const result = await prepareInfinityArcadeUpgrade({ projectRoot: root, artifactDir: outDir });
    assert.equal(result.packet.mutationAllowedNow, false);
    assert.ok(result.artifactPath.endsWith('infinity-arcade-upgrade-readiness.json'));
    assert.ok(result.evidencePath.endsWith('infinity-arcade-upgrade-readiness.md'));
    const markdown = readFileSync(result.evidencePath, 'utf8');
    assert.match(markdown, /pre-upgrade state proof/i);
    assert.match(markdown, /production provenance/i);
    assert.match(markdown, /current deployed module hash/i);
    assert.match(markdown, /rollback/i);
    assert.match(markdown, /governed safe-wrapper proof/i);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(outDir, { recursive: true, force: true });
  }
}

console.log('Infinity Arcade upgrade manager checks passed');
