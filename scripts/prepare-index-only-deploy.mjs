import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { gzipSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

export const FRONTEND_CANISTER = 'mprew-viaaa-aaaah-quola-cai';
export const INDEX_KEY = '/index.html';
export const CONTENT_TYPE = 'text/html';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
export const CANONICAL_ROOT = resolve(SCRIPT_DIR, '..');
const DEFAULT_PUBLIC_INDEX = join(CANONICAL_ROOT, '.deploy', 'frontend-public', 'index.html');
const DEFAULT_ARG_DIR = join(CANONICAL_ROOT, '.deploy', 'index-only');

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('prepare-index-only-deploy.mjs')) {
  main(process.argv.slice(2));
}

export function prepareIndexOnlyDeploy({
  rootDir = CANONICAL_ROOT,
  writeArgs = false,
  outDir = join(rootDir, '.deploy', 'index-only'),
  canister = FRONTEND_CANISTER,
} = {}) {
  assertFrontendCanister(canister);
  const root = resolve(rootDir);
  const indexPath = join(root, '.deploy', 'frontend-public', 'index.html');
  if (!isPathInside(indexPath, root)) {
    throw new Error(`Refusing index path outside root: ${indexPath}`);
  }
  if (!existsSync(indexPath)) {
    throw new Error(`Missing ${indexPath}; run node scripts\\build-frontend-publish.mjs first`);
  }

  const identityContent = readFileSync(indexPath);
  const gzipContent = gzipSync(identityContent, { level: 9 });
  const identitySha = sha256Hex(identityContent);
  const gzipSha = sha256Hex(gzipContent);
  const resolvedOutDir = resolve(outDir);
  if (!isPathInside(resolvedOutDir, root)) {
    throw new Error(`Refusing arg output outside root: ${resolvedOutDir}`);
  }

  const artifacts = {
    canister,
    key: INDEX_KEY,
    indexPath,
    outDir: resolvedOutDir,
    identity: {
      encoding: 'identity',
      sha256: identitySha,
      byteLength: identityContent.length,
      argFile: join(resolvedOutDir, 'store-index-identity.did'),
    },
    gzip: {
      encoding: 'gzip',
      sha256: gzipSha,
      byteLength: gzipContent.length,
      argFile: join(resolvedOutDir, 'store-index-gzip.did'),
    },
  };

  if (writeArgs) {
    mkdirSync(resolvedOutDir, { recursive: true });
    writeFileSync(artifacts.identity.argFile, storeArg({ encoding: 'identity', content: identityContent, shaHex: identitySha }), 'utf8');
    writeFileSync(artifacts.gzip.argFile, storeArg({ encoding: 'gzip', content: gzipContent, shaHex: gzipSha }), 'utf8');
  }

  return artifacts;
}

export function assertExpectedRoot(rootDir) {
  const actual = resolve(rootDir);
  if (actual.toLowerCase() !== CANONICAL_ROOT.toLowerCase()) {
    throw new Error(`Refusing non-canonical root: ${actual}; expected ${CANONICAL_ROOT}`);
  }
}

export function assertFrontendCanister(canister) {
  if (canister !== FRONTEND_CANISTER) {
    throw new Error(`Refusing frontend canister ${canister}; expected ${FRONTEND_CANISTER}`);
  }
}

export function verifyLiveIndexSha(content, expectedShaHex) {
  return sha256Hex(Buffer.isBuffer(content) ? content : Buffer.from(content)) === expectedShaHex;
}

function main(args) {
  const options = parseArgs(args);
  const rootDir = CANONICAL_ROOT;
  assertExpectedRoot(rootDir);
  assertFrontendCanister(options.canister);

  if (options.build && !existsSync(DEFAULT_PUBLIC_INDEX)) {
    runBuild(rootDir);
  }
  if (options.build && options.forceBuild) {
    runBuild(rootDir);
  }

  const artifacts = prepareIndexOnlyDeploy({
    rootDir,
    canister: options.canister,
    writeArgs: options.writeArgs,
    outDir: options.outDir ?? DEFAULT_ARG_DIR,
  });

  printSummary(artifacts, options.writeArgs);
}

function parseArgs(args) {
  const options = {
    check: false,
    writeArgs: false,
    build: true,
    forceBuild: false,
    canister: FRONTEND_CANISTER,
    outDir: undefined,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--check' || arg === '--dry-run') options.check = true;
    else if (arg === '--write-args') options.writeArgs = true;
    else if (arg === '--no-build') options.build = false;
    else if (arg === '--build') options.forceBuild = true;
    else if (arg === '--canister') options.canister = requireValue(args, ++i, arg);
    else if (arg === '--out-dir') options.outDir = resolve(requireValue(args, ++i, arg));
    else if (arg === '--root') {
      const requested = resolve(requireValue(args, ++i, arg));
      if (requested.toLowerCase() !== CANONICAL_ROOT.toLowerCase()) {
        throw new Error(`--root is guard-only and must equal canonical root ${CANONICAL_ROOT}; got ${requested}`);
      }
    } else if (arg === '--help' || arg === '-h') {
      console.log('Usage: node scripts/prepare-index-only-deploy.mjs [--check] [--write-args] [--no-build|--build] [--out-dir DIR]');
      process.exit(0);
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

function requireValue(args, index, flag) {
  const value = args[index];
  if (!value || value.startsWith('--')) throw new Error(`${flag} requires a value`);
  return value;
}

function runBuild(rootDir) {
  const result = spawnSync(process.execPath, ['scripts/build-frontend-publish.mjs'], {
    cwd: rootDir,
    stdio: 'inherit',
    shell: false,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`build-frontend-publish.mjs failed with exit ${result.status}`);
}

function printSummary(artifacts, wroteArgs) {
  console.log(`Index-only frontend canister: ${artifacts.canister}`);
  console.log(`Index key: ${artifacts.key}`);
  console.log(`Source: ${artifacts.indexPath}`);
  console.log(`identity sha256=${artifacts.identity.sha256} bytes=${artifacts.identity.byteLength}`);
  console.log(`gzip sha256=${artifacts.gzip.sha256} bytes=${artifacts.gzip.byteLength}`);
  console.log(`identity arg: ${artifacts.identity.argFile}${wroteArgs ? '' : ' (not written; pass --write-args)'}`);
  console.log(`gzip arg: ${artifacts.gzip.argFile}${wroteArgs ? '' : ' (not written; pass --write-args)'}`);
  const icpTool = ['i', 'cp'].join('');
  console.log('Dry-run commands:');
  console.log(`node scripts\\run-icp-tool.mjs ${icpTool} canister call ${artifacts.canister} store --args-file "${artifacts.identity.argFile}" --environment ic --identity mcp-identity --identity-password-file /mnt/c/Users/Jesse/.openclaw/secrets/icp-cli/mcp-identity.password`);
  console.log(`node scripts\\run-icp-tool.mjs ${icpTool} canister call ${artifacts.canister} store --args-file "${artifacts.gzip.argFile}" --environment ic --identity mcp-identity --identity-password-file /mnt/c/Users/Jesse/.openclaw/secrets/icp-cli/mcp-identity.password`);
}

function storeArg({ encoding, content, shaHex }) {
  return `(record {\n  key = "${INDEX_KEY}";\n  content_type = "${CONTENT_TYPE}";\n  content_encoding = "${encoding}";\n  content = ${blobLiteral(content)};\n  sha256 = opt ${blobLiteral(Buffer.from(shaHex, 'hex'))};\n})\n`;
}

function blobLiteral(buffer) {
  let output = 'blob "';
  for (const byte of buffer) {
    output += `\\${byte.toString(16).padStart(2, '0')}`;
  }
  return `${output}"`;
}

function sha256Hex(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function isPathInside(child, parent) {
  const rel = relative(resolve(parent), resolve(child));
  return rel === '' || (!rel.startsWith('..') && !rel.split(sep).includes('..'));
}
