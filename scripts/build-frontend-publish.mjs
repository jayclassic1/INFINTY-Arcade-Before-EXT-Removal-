import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';

const ROOT = resolve(new URL('..', import.meta.url).pathname.replace(/^\/(.:\/)/, '$1'));
const DEFAULT_OUT = join(ROOT, '.deploy', 'frontend-public');

const ROOT_PUBLIC_FILES = [
  'index.html',
  'manifesto.txt',
  'legal-privacy.md',
  'legal-tos.md',
  'dfinity-bundle.js',
  'arcades-flow.jpg',
  'artists-gashapon-system.png',
  'artists-nft-revenue-splits.webp',
  'backroom-bg.jpg',
  'boardroom.jpg',
  'dao-flow-overview.jpg',
  'dao-flow-overview.png',
  'digitar-base.png',
  'digitar-mask.png',
  'forums-bg.jpg',
  'fullcatalog.jpg',
  'gashapon-bg.jpg',
  'landing-v6.jpg',
  'manifesto-bg.jpg',
  'manifesto-popup-bg.jpg',
  'manual-page1.jpg',
  'manual-page2.jpg',
  'mycollection.jpg',
  'prizebooth.jpg',
  'showroom-v3.jpg',
  'the-hole-approved-bg.jpg',
];

const GAME_PUBLIC_EXTENSIONS = new Set([
  '.html',
  '.js',
  '.css',
  '.json',
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.svg',
  '.mp3',
  '.wav',
  '.ogg',
  '.m4a',
  '.wasm',
]);

const FORBIDDEN_OUTPUT_PREFIXES = [
  'backend/',
  'docs/',
  'scripts/',
  'tasks/',
  '.openclaw-review/',
  '.git/',
  '.deploy/',
  'node_modules/',
];

const FORBIDDEN_OUTPUT_FILES = new Set([
  'CANONICAL.md',
  'PROJECT.md',
  'PROJECT_ROOT_STRUCTURE.md',
  'README_CANONICAL_DEPLOY.md',
  'ROLLBACK.md',
  'deploy-manifest.json',
  '.deployignore',
  '.gitignore',
]);

const outDir = parseOutDir(process.argv.slice(2));
const resolvedOutDir = resolve(outDir);
if (resolvedOutDir === ROOT || !isPathInside(resolvedOutDir, ROOT) && !isPathInside(resolvedOutDir, resolve(process.env.TEMP ?? process.env.TMP ?? ROOT))) {
  throw new Error(`Refusing unsafe output directory: ${resolvedOutDir}`);
}

rmSync(resolvedOutDir, { recursive: true, force: true });
mkdirSync(resolvedOutDir, { recursive: true });

const selectedFiles = new Set(ROOT_PUBLIC_FILES);
for (const gameFile of listFiles(join(ROOT, 'games'))) {
  const rel = `games/${gameFile}`;
  if (GAME_PUBLIC_EXTENSIONS.has(extensionOf(rel))) {
    selectedFiles.add(rel);
  }
}

const copied = [];
for (const rel of [...selectedFiles].sort()) {
  validateRelativeOutputPath(rel);
  const src = join(ROOT, ...rel.split('/'));
  if (!existsSync(src)) {
    throw new Error(`Required public asset missing: ${rel}`);
  }
  if (!statSync(src).isFile()) {
    throw new Error(`Public payload entry is not a file: ${rel}`);
  }
  const dest = join(resolvedOutDir, ...rel.split('/'));
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(src, dest);
  copied.push(rel);
}

const manifest = [...copied, 'deploy-manifest.txt'].sort();
writeFileSync(join(resolvedOutDir, 'deploy-manifest.txt'), `${manifest.join('\n')}\n`, 'utf8');

console.log(`Frontend publish payload written to ${resolvedOutDir}`);
console.log(`Files: ${manifest.length}`);
console.log(manifest.join('\n'));

function parseOutDir(args) {
  const outIndex = args.indexOf('--out');
  if (outIndex === -1) return DEFAULT_OUT;
  const value = args[outIndex + 1];
  if (!value) throw new Error('--out requires a directory value');
  return value;
}

function listFiles(dir) {
  if (!existsSync(dir)) return [];
  const output = [];
  walk(dir, '');
  return output.sort();

  function walk(current, relBase) {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const rel = relBase ? `${relBase}/${entry.name}` : entry.name;
      const full = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full, rel);
      } else if (entry.isFile()) {
        output.push(rel);
      }
    }
  }
}

function extensionOf(rel) {
  const name = rel.toLowerCase();
  const dot = name.lastIndexOf('.');
  return dot === -1 ? '' : name.slice(dot);
}

function validateRelativeOutputPath(rel) {
  if (rel.includes('\\') || rel.startsWith('/') || rel.includes('..')) {
    throw new Error(`Unsafe relative output path: ${rel}`);
  }
  if (FORBIDDEN_OUTPUT_PREFIXES.some((prefix) => rel.startsWith(prefix))) {
    throw new Error(`Forbidden internal path selected for publish payload: ${rel}`);
  }
  if (FORBIDDEN_OUTPUT_FILES.has(rel)) {
    throw new Error(`Forbidden internal file selected for publish payload: ${rel}`);
  }
}

function isPathInside(child, parent) {
  const rel = relative(parent, child);
  return rel === '' || (!rel.startsWith('..') && !rel.split(sep).includes('..'));
}
