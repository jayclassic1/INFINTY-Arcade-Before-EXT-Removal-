#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PROJECT_ROOT = resolve(SCRIPT_DIR, '..');
const DEFAULT_EVIDENCE_DIR = 'C:\\Users\\Jesse\\OpenClawEvidence\\icp-arcade-icp-tipping';
const READINESS_BASENAME = 'infinity-arcade-upgrade-readiness';
const RELEASE_MANIFEST_RELATIVE_PATH = '.releases/latest.json';
const LOCAL_BUILD_TOKEN = ['d', 'fx'].join('');
const RAW_LOCAL_BUILD_TOKEN = `raw_${LOCAL_BUILD_TOKEN}`;
const RAW_LOCAL_BUILD_FLAG = `raw-${LOCAL_BUILD_TOKEN}`;
const RAW_LOCAL_BUILD_CAMEL = `raw${LOCAL_BUILD_TOKEN[0].toUpperCase()}${LOCAL_BUILD_TOKEN.slice(1)}`;

export const REQUIRED_BACKEND_METHODS = Object.freeze([
  'isAdminPrincipal',
  'recordIcpTip',
  'getGameIcpTipSummary',
  'getRecentGameIcpTips',
]);

export const INFINITY_ARCADE_UPGRADE_LANE = Object.freeze({
  laneId: 'infinity-arcade-existing-backend-upgrade-readiness-v1',
  projectId: 'ICP-ARCADE',
  projectSlug: 'infinity-arcade-Jay',
  display: 'Infinity Arcade / Jay Nolan',
  projectRoot: DEFAULT_PROJECT_ROOT,
  network: 'ic',
  operation: 'backend_upgrade',
  canisters: Object.freeze({
    backend: 'pifyq-raaaa-aaaab-agrqq-cai',
    frontend: 'mprew-viaaa-aaaah-quola-cai',
  }),
  genericLane: Object.freeze({
    provider: 'GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER',
    mapping: 'pifyq Infinity Arcade existing backend upgrade',
    mutationAllowedNow: false,
    proofRequired: 'governed runtime-provider safe-wrapper proof',
  }),
  candidate: Object.freeze({
    wasm: Object.freeze({ path: 'backend/.build/arcade_backend.wasm' }),
    did: Object.freeze({ path: 'backend/.build/arcade_backend.did' }),
  }),
});

const BLOCKED_FLAGS = new Set([
  'execute', 'live', 'frontendUpload', 'frontend-upload', 'newCanister', 'new-canister', 'fullStack', 'full-stack',
  'controller', 'controllers', 'cycles', 'identity', 'secret', 'secrets', 'gatewayRestart', 'gateway-restart',
  RAW_LOCAL_BUILD_CAMEL, RAW_LOCAL_BUILD_FLAG, LOCAL_BUILD_TOKEN, 'upgrade', 'deploy', 'install', 'upload',
  'installCode', 'install-code', 'install_code', 'liveMutation', 'live-mutation', 'live_mutation',
  'backendUpgrade', 'backend-upgrade', 'backend_upgrade',
]);
const BLOCKED_OPERATIONS = new Set([
  'frontend_upload', 'new_canister', 'full_stack', 'controller_change', 'cycles_topup', 'identity_change',
  'secret_access', RAW_LOCAL_BUILD_TOKEN, 'gateway_restart', 'deploy', 'upgrade', 'install', 'upload',
  'install_code', 'install-code', 'installCode', 'live_mutation', 'live-mutation', 'liveMutation',
]);
const NORMALIZED_BLOCKED_KEY_TOKENS = Object.freeze([
  'execute', 'live', 'deploy', 'upgrade', 'install', 'upload', 'mutation', 'controller', 'cycle', 'identity', 'secret',
]);
const NORMALIZED_BLOCKED_KEYS = new Set([
  ...[...BLOCKED_FLAGS].map(normalizeOptionToken),
  'frontendupload', 'newcanister', 'fullstack', 'gatewayrestart', 'rawdfx', 'installcode', 'livemutation', 'backendupgrade',
]);
const NORMALIZED_BLOCKED_VALUES = new Set([
  ...[...BLOCKED_OPERATIONS].map(normalizeOptionToken),
  'frontendupload', 'newcanister', 'fullstack', 'controllerchange', 'cyclestopup', 'identitychange',
  'secretaccess', 'gatewayrestart', 'rawdfx', 'installcode', 'livemutation',
]);
const SOURCE_EXTENSIONS = new Set(['.mo', '.did', '.json', '.toml', '.lock', '.mjs', '.js', '.ts', '.sh', '.ps1']);
const EXCLUDED_SOURCE_DIRS = new Set(['.build', `.${LOCAL_BUILD_TOKEN}`, '.pytest_cache', '__pycache__', '.releases', 'node_modules']);

function normalizeOptionToken(value) {
  return String(value ?? '').replace(/[^a-z0-9]/gi, '').toLowerCase();
}

function normalizeProjectRoot(projectRoot = DEFAULT_PROJECT_ROOT) {
  return resolve(projectRoot);
}

function toPosixRelative(projectRoot, absolutePath) {
  return relative(projectRoot, absolutePath).split(sep).join('/');
}

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function inspectCandidateFile(projectRoot, relativePath) {
  const absolutePath = resolve(projectRoot, relativePath);
  const exists = existsSync(absolutePath);
  const stats = exists ? statSync(absolutePath) : null;
  return {
    relativePath,
    absolutePath,
    exists,
    sha256: exists ? sha256File(absolutePath) : null,
    mtime: stats ? stats.mtime.toISOString() : null,
    mtimeMs: stats ? stats.mtimeMs : null,
    size: stats ? stats.size : null,
  };
}

function latestRelevantBackendSource(projectRoot) {
  const backendRoot = resolve(projectRoot, 'backend');
  let latest = null;
  function visit(dir) {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        if (EXCLUDED_SOURCE_DIRS.has(entry.name)) continue;
        visit(join(dir, entry.name));
        continue;
      }
      if (!entry.isFile()) continue;
      const absolutePath = join(dir, entry.name);
      const ext = entry.name.includes('.') ? entry.name.slice(entry.name.lastIndexOf('.')) : '';
      if (!SOURCE_EXTENSIONS.has(ext) && entry.name !== 'mops.toml') continue;
      const stats = statSync(absolutePath);
      if (!latest || stats.mtimeMs > latest.mtimeMs) {
        latest = {
          relativePath: toPosixRelative(projectRoot, absolutePath),
          absolutePath,
          mtime: stats.mtime.toISOString(),
          mtimeMs: stats.mtimeMs,
        };
      }
    }
  }
  visit(backendRoot);
  return latest;
}

function optionsFromArgv(argv) {
  const options = {};
  for (const raw of argv) {
    if (!raw.startsWith('--')) continue;
    const [key, value = 'true'] = raw.slice(2).split('=', 2);
    options[key] = value === 'true' ? true : value === 'false' ? false : value;
  }
  return options;
}

export function rejectUnsafeOptions(options = {}) {
  const blocked = [];
  for (const [key, value] of Object.entries(options)) {
    if (value === false || value === undefined || value === null || value === '') continue;

    const normalizedKey = normalizeOptionToken(key);
    const normalizedValue = normalizeOptionToken(value);
    const keyImpliesLiveMutation = NORMALIZED_BLOCKED_KEYS.has(normalizedKey)
      || NORMALIZED_BLOCKED_KEY_TOKENS.some((token) => normalizedKey.includes(token));

    if (BLOCKED_FLAGS.has(key) || keyImpliesLiveMutation) blocked.push(`${key}=${value}`);
    if (key === 'operation' && value !== INFINITY_ARCADE_UPGRADE_LANE.operation) blocked.push(`operation=${value}`);
    if (key !== 'operation' && (BLOCKED_OPERATIONS.has(String(value)) || NORMALIZED_BLOCKED_VALUES.has(normalizedValue))) {
      blocked.push(`${key}=${value}`);
    }
  }
  if (blocked.length > 0) {
    throw new Error(`BLOCKED_UNSAFE_UPGRADE_OPTION: ${[...new Set(blocked)].join(', ')}. This project-local manager is readiness-only; live mutation requires governed safe-wrapper proof and separate approval.`);
  }
}

function inspectMethods(didText) {
  const present = REQUIRED_BACKEND_METHODS.filter((method) => new RegExp(`\\b${method}\\b`).test(didText));
  const missing = REQUIRED_BACKEND_METHODS.filter((method) => !present.includes(method));
  return { required: [...REQUIRED_BACKEND_METHODS], present, missing, pass: missing.length === 0 };
}

function inspectFreshness(projectRoot, wasm, did) {
  const latestSource = latestRelevantBackendSource(projectRoot);
  const artifactEntries = [wasm, did].filter((artifact) => artifact.exists);
  const oldestArtifact = artifactEntries.length === 0
    ? null
    : artifactEntries.reduce((oldest, artifact) => artifact.mtimeMs < oldest.mtimeMs ? artifact : oldest, artifactEntries[0]);
  const missingArtifacts = [wasm, did].filter((artifact) => !artifact.exists).map((artifact) => artifact.relativePath);
  const pass = missingArtifacts.length === 0 && Boolean(latestSource) && Boolean(oldestArtifact) && oldestArtifact.mtimeMs >= latestSource.mtimeMs;
  return {
    pass,
    latestSource,
    oldestArtifact: oldestArtifact ? {
      relativePath: oldestArtifact.relativePath,
      absolutePath: oldestArtifact.absolutePath,
      mtime: oldestArtifact.mtime,
      mtimeMs: oldestArtifact.mtimeMs,
    } : null,
    missingArtifacts,
    rule: 'backend/.build WASM and DID mtimes must be newer than or equal to the latest relevant backend source mtime',
  };
}

function isSha256Hex(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/i.test(value);
}

function isGitShaHex(value) {
  return typeof value === 'string' && /^[0-9a-f]{40}$/i.test(value);
}

function inspectProductionProvenance(projectRoot) {
  const absolutePath = resolve(projectRoot, RELEASE_MANIFEST_RELATIVE_PATH);
  const base = {
    schema: 'infinity-arcade-production-provenance/v1',
    source: 'project_release_manifest',
    manifest: {
      relativePath: RELEASE_MANIFEST_RELATIVE_PATH,
      absolutePath,
      exists: existsSync(absolutePath),
    },
    governedLiveStateProofRequired: true,
    governedLiveStateProofMatched: null,
    pass: false,
    status: 'blocked_production_provenance_required',
    reason: null,
  };

  if (!base.manifest.exists) {
    return {
      ...base,
      reason: 'Project release manifest .releases/latest.json is required to bind current deployed module metadata and rollback hash before governed live-state proof.',
    };
  }

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(absolutePath, 'utf8'));
  } catch (error) {
    return {
      ...base,
      reason: `Release manifest is not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    };
  }

  const blockers = [];
  if (manifest.canister_id !== INFINITY_ARCADE_UPGRADE_LANE.canisters.backend) {
    blockers.push(`canister_id must be ${INFINITY_ARCADE_UPGRADE_LANE.canisters.backend}`);
  }
  if (!isSha256Hex(manifest.wasm_hash)) blockers.push('wasm_hash must be a SHA-256 hex module hash');
  if (!isSha256Hex(manifest.previous_hash)) blockers.push('previous_hash must be a SHA-256 hex rollback module hash');
  if (!isGitShaHex(manifest.git_commit)) blockers.push('git_commit must be a 40-character source commit hash');
  if (manifest.mode !== 'upgrade') blockers.push('mode must be upgrade for existing-backend rollback provenance');

  const rollbackBundle = {
    canisterId: manifest.canister_id ?? null,
    currentModuleHash: isSha256Hex(manifest.wasm_hash) ? manifest.wasm_hash.toLowerCase() : null,
    rollbackModuleHash: isSha256Hex(manifest.previous_hash) ? manifest.previous_hash.toLowerCase() : null,
    sourceGitCommit: typeof manifest.git_commit === 'string' ? manifest.git_commit : null,
    releaseTimestamp: typeof manifest.timestamp === 'string' ? manifest.timestamp : null,
    releaseVersion: typeof manifest.version === 'string' ? manifest.version : null,
    mode: typeof manifest.mode === 'string' ? manifest.mode : null,
    wasmSize: Number.isFinite(manifest.wasm_size) ? manifest.wasm_size : null,
    notes: typeof manifest.notes === 'string' ? manifest.notes : null,
    manifestRelativePath: RELEASE_MANIFEST_RELATIVE_PATH,
  };

  if (blockers.length > 0) {
    return {
      ...base,
      currentDeployedModuleHash: rollbackBundle.currentModuleHash,
      rollbackBundle,
      reason: blockers.join('; '),
    };
  }

  return {
    ...base,
    pass: true,
    status: 'ready_project_local_release_provenance',
    reason: 'Project-local release manifest binds the expected current deployed module hash and rollback module hash; governed live-state proof must still confirm the live canister hash before mutation.',
    currentDeployedModuleHash: rollbackBundle.currentModuleHash,
    rollbackBundle,
  };
}

export async function buildInfinityArcadeUpgradePacket({ projectRoot = DEFAULT_PROJECT_ROOT, options = {} } = {}) {
  rejectUnsafeOptions(options);
  const root = normalizeProjectRoot(projectRoot);
  const wasm = inspectCandidateFile(root, INFINITY_ARCADE_UPGRADE_LANE.candidate.wasm.path);
  const did = inspectCandidateFile(root, INFINITY_ARCADE_UPGRADE_LANE.candidate.did.path);
  const didText = did.exists ? readFileSync(did.absolutePath, 'utf8') : '';
  const requiredBackendMethods = inspectMethods(didText);
  const freshness = inspectFreshness(root, wasm, did);
  const productionProvenance = inspectProductionProvenance(root);
  const candidateArtifactsPresent = wasm.exists && did.exists;
  const status = !candidateArtifactsPresent
    ? 'blocked_candidate_artifacts_missing'
    : !freshness.pass
      ? 'blocked_candidate_artifacts_stale'
      : !requiredBackendMethods.pass
        ? 'blocked_candidate_did_methods_missing'
        : !productionProvenance.pass
          ? 'blocked_production_provenance_required'
        : 'ready_readiness_only';

  return {
    schema: 'infinity-arcade-upgrade-manager-packet/v1',
    laneId: INFINITY_ARCADE_UPGRADE_LANE.laneId,
    status,
    generatedAt: new Date().toISOString(),
    projectId: INFINITY_ARCADE_UPGRADE_LANE.projectId,
    projectRoot: root,
    network: INFINITY_ARCADE_UPGRADE_LANE.network,
    operation: INFINITY_ARCADE_UPGRADE_LANE.operation,
    backendCanister: INFINITY_ARCADE_UPGRADE_LANE.canisters.backend,
    frontendCanister: INFINITY_ARCADE_UPGRADE_LANE.canisters.frontend,
    canisters: { ...INFINITY_ARCADE_UPGRADE_LANE.canisters },
    genericLane: { ...INFINITY_ARCADE_UPGRADE_LANE.genericLane },
    candidate: { wasm, did },
    candidateWasmHash: wasm.sha256,
    candidateDidHash: did.sha256,
    requiredBackendMethods,
    freshness,
    productionProvenance,
    stableMigrationAndTestChecklist: [
      'Run npm run backend:build before generating this packet.',
      'Confirm backend/.build/arcade_backend.wasm and backend/.build/arcade_backend.did are the candidate artifacts.',
      'Confirm .build DID contains isAdminPrincipal, recordIcpTip, getGameIcpTipSummary, and getRecentGameIcpTips.',
      'Run node scripts/test-infinity-arcade-upgrade-manager.mjs.',
      'Run node scripts/test-jay-backend-upgrade-lane.mjs for compatibility coverage.',
      'Run node scripts/test-icp-tip-ui-contract.mjs when UI contract changed.',
    ],
    preUpgradeStateProofRequired: [
      'Governed safe-wrapper proof for GENERIC_EXISTING_BACKEND_UPGRADE_SAFE_WRAPPER_PROVIDER.',
      'Certified current backend module hash for pifyq before execution.',
      'Certified live module hash must match productionProvenance.currentDeployedModuleHash before install_code is authorized.',
      'Canister status/controllers proof from approved safe wrapper only, not this readiness script.',
      'Reviewed candidate WASM/DID hashes matching this packet.',
    ],
    rollbackPlaceholders: [
      'Use productionProvenance.rollbackBundle.rollbackModuleHash as the project-local rollback module hash candidate.',
      'Governed live-state proof must confirm productionProvenance.currentDeployedModuleHash before live execution.',
      'Prepare post-rollback method/hash verification checklist.',
    ],
    postVerifyPlaceholders: [
      'Certified backend module hash equals candidateWasmHash.',
      'Backend Candid/method surface includes isAdminPrincipal plus all required tipping methods.',
      'Tip receipt smoke query succeeds without frontend upload assumptions.',
      'Frontend canister remains unchanged unless separately authorized after backend verification.',
    ],
    deniedActions: [
      'live execution', 'backend upgrade', 'frontend upload', 'new canister', 'full-stack deploy', 'controller change',
      'cycles operation', 'identity access/change', 'secret access', `raw ${LOCAL_BUILD_TOKEN}`, 'gateway restart',
    ],
    mutationAllowedNow: false,
    execution: {
      allowed: false,
      reason: 'Readiness packet only. Live execution remains blocked until governed safe-wrapper proof and separate approval exist.',
      governedSafeWrapperProofRequired: true,
    },
  };
}

function renderMarkdown(packet) {
  return `# Infinity Arcade Upgrade Manager Readiness\n\n` +
    `Generated: ${packet.generatedAt}\n\n` +
    `## Status\n\n` +
    `- Status: \`${packet.status}\`\n` +
    `- Mutation allowed now: \`${packet.mutationAllowedNow}\`\n` +
    `- Execution reason: ${packet.execution.reason}\n\n` +
    `## Generic lane packet\n\n` +
    `- Schema: \`${packet.schema}\`\n` +
    `- Lane id: \`${packet.laneId}\`\n` +
    `- Generic lane provider: \`${packet.genericLane.provider}\`\n` +
    `- Generic lane mapping: ${packet.genericLane.mapping}\n` +
    `- Project id: \`${packet.projectId}\`\n` +
    `- Project root: \`${packet.projectRoot}\`\n` +
    `- Backend canister: \`${packet.backendCanister}\`\n` +
    `- Frontend canister: \`${packet.frontendCanister}\`\n` +
    `- Candidate WASM: \`${packet.candidate.wasm.relativePath}\`\n` +
    `- Candidate WASM SHA-256: \`${packet.candidateWasmHash}\`\n` +
    `- Candidate DID: \`${packet.candidate.did.relativePath}\`\n` +
    `- Candidate DID SHA-256: \`${packet.candidateDidHash}\`\n\n` +
    `## Required backend methods\n\n` +
    `- Required: ${packet.requiredBackendMethods.required.join(', ')}\n` +
    `- Present: ${packet.requiredBackendMethods.present.join(', ') || 'none'}\n` +
    `- Missing: ${packet.requiredBackendMethods.missing.join(', ') || 'none'}\n` +
    `- Pass: ${packet.requiredBackendMethods.pass}\n\n` +
    `## Artifact freshness\n\n` +
    `- Rule: ${packet.freshness.rule}\n` +
    `- Pass: ${packet.freshness.pass}\n` +
    `- Latest source: ${packet.freshness.latestSource ? `\`${packet.freshness.latestSource.relativePath}\` at ${packet.freshness.latestSource.mtime}` : 'none'}\n` +
    `- Oldest artifact: ${packet.freshness.oldestArtifact ? `\`${packet.freshness.oldestArtifact.relativePath}\` at ${packet.freshness.oldestArtifact.mtime}` : 'none'}\n` +
    `- Missing artifacts: ${packet.freshness.missingArtifacts.join(', ') || 'none'}\n\n` +
    `## Production provenance\n\n` +
    `- Status: \`${packet.productionProvenance.status}\`\n` +
    `- Pass: ${packet.productionProvenance.pass}\n` +
    `- Reason: ${packet.productionProvenance.reason}\n` +
    `- Manifest: \`${packet.productionProvenance.manifest.relativePath}\`\n` +
    `- Current deployed module hash: \`${packet.productionProvenance.currentDeployedModuleHash || 'unavailable'}\`\n` +
    `- Rollback module hash: \`${packet.productionProvenance.rollbackBundle?.rollbackModuleHash || 'unavailable'}\`\n` +
    `- Rollback source commit: \`${packet.productionProvenance.rollbackBundle?.sourceGitCommit || 'unavailable'}\`\n` +
    `- Governed live-state proof required: ${packet.productionProvenance.governedLiveStateProofRequired}\n\n` +
    `## Stable migration/test checklist\n\n${packet.stableMigrationAndTestChecklist.map((item) => `- ${item}`).join('\n')}\n\n` +
    `## Pre-upgrade state proof required before live execution\n\n${packet.preUpgradeStateProofRequired.map((item) => `- ${item}`).join('\n')}\n\n` +
    `## Rollback placeholders\n\n${packet.rollbackPlaceholders.map((item) => `- ${item}`).join('\n')}\n\n` +
    `## Post-verify placeholders\n\n${packet.postVerifyPlaceholders.map((item) => `- ${item}`).join('\n')}\n\n` +
    `## Fail-closed denied actions\n\n${packet.deniedActions.map((item) => `- ${item}`).join('\n')}\n`;
}

function safeWrite(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content, 'utf8');
}

export async function prepareInfinityArcadeUpgrade({ projectRoot = DEFAULT_PROJECT_ROOT, artifactDir = DEFAULT_EVIDENCE_DIR, options = {} } = {}) {
  const packet = await buildInfinityArcadeUpgradePacket({ projectRoot, options });
  const outDir = isAbsolute(artifactDir) ? artifactDir : resolve(projectRoot, artifactDir);
  const artifactPath = join(outDir, `${READINESS_BASENAME}.json`);
  const evidencePath = join(outDir, `${READINESS_BASENAME}.md`);
  safeWrite(artifactPath, `${JSON.stringify(packet, null, 2)}\n`);
  safeWrite(evidencePath, renderMarkdown(packet));
  return { packet, artifactPath, evidencePath };
}

async function main() {
  const cliOptions = optionsFromArgv(process.argv.slice(2));
  const artifactDir = typeof cliOptions.artifactDir === 'string' ? cliOptions.artifactDir : DEFAULT_EVIDENCE_DIR;
  delete cliOptions.artifactDir;
  try {
    const result = await prepareInfinityArcadeUpgrade({ options: cliOptions, artifactDir });
    console.log(JSON.stringify({
      status: result.packet.status,
      mutationAllowedNow: result.packet.mutationAllowedNow,
      artifactPath: result.artifactPath,
      evidencePath: result.evidencePath,
      backendCanister: result.packet.backendCanister,
      frontendCanister: result.packet.frontendCanister,
      genericLaneProvider: result.packet.genericLane.provider,
      candidateWasmHash: result.packet.candidateWasmHash,
      candidateDidHash: result.packet.candidateDidHash,
      requiredMethodsPresent: result.packet.requiredBackendMethods.present,
      requiredMethodsMissing: result.packet.requiredBackendMethods.missing,
      freshnessPass: result.packet.freshness.pass,
      productionProvenanceStatus: result.packet.productionProvenance.status,
      currentDeployedModuleHash: result.packet.productionProvenance.currentDeployedModuleHash,
      rollbackModuleHash: result.packet.productionProvenance.rollbackBundle?.rollbackModuleHash,
    }, null, 2));
    process.exitCode = result.packet.status === 'ready_readiness_only' ? 0 : 1;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 2;
  }
}

if (import.meta.url === `file://${process.argv[1]?.replaceAll('\\\\', '/')}` || process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
