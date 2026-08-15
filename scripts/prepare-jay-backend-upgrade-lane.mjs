#!/usr/bin/env node
import { fileURLToPath } from 'node:url';

import {
  INFINITY_ARCADE_UPGRADE_LANE,
  buildInfinityArcadeUpgradePacket,
  prepareInfinityArcadeUpgrade,
  rejectUnsafeOptions,
} from './prepare-infinity-arcade-upgrade.mjs';

export const JAY_BACKEND_LANE = Object.freeze({
  projectId: INFINITY_ARCADE_UPGRADE_LANE.projectId,
  projectSlug: INFINITY_ARCADE_UPGRADE_LANE.projectSlug,
  display: INFINITY_ARCADE_UPGRADE_LANE.display,
  projectRoot: INFINITY_ARCADE_UPGRADE_LANE.projectRoot,
  backendCanister: INFINITY_ARCADE_UPGRADE_LANE.canisters.backend,
  frontendCanister: INFINITY_ARCADE_UPGRADE_LANE.canisters.frontend,
  network: INFINITY_ARCADE_UPGRADE_LANE.network,
  operation: INFINITY_ARCADE_UPGRADE_LANE.operation,
  genericLane: INFINITY_ARCADE_UPGRADE_LANE.genericLane,
  candidate: INFINITY_ARCADE_UPGRADE_LANE.candidate,
});

export { rejectUnsafeOptions };

export async function buildBackendUpgradePacket({ projectRoot, options = {} } = {}) {
  return buildInfinityArcadeUpgradePacket({ projectRoot, options });
}

export async function prepareBackendUpgradeReadiness({ projectRoot, artifactDir, options = {} } = {}) {
  return prepareInfinityArcadeUpgrade({ projectRoot, artifactDir, options });
}

async function main() {
  const cliOptions = {};
  for (const raw of process.argv.slice(2)) {
    if (!raw.startsWith('--')) continue;
    const [key, value = 'true'] = raw.slice(2).split('=', 2);
    cliOptions[key] = value === 'true' ? true : value === 'false' ? false : value;
  }
  const artifactDir = typeof cliOptions.artifactDir === 'string' ? cliOptions.artifactDir : undefined;
  delete cliOptions.artifactDir;
  try {
    const result = await prepareBackendUpgradeReadiness({ artifactDir, options: cliOptions });
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
