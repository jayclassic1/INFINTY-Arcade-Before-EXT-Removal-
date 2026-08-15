import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, sep } from 'node:path';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const outDir = mkdtempSync(join(tmpdir(), 'ia-frontend-publish-'));

try {
  const result = spawnSync(process.execPath, ['scripts/build-frontend-publish.mjs', '--out', outDir], {
    cwd: root,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, `publish builder failed\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);

  const files = listFiles(outDir);
  const fileSet = new Set(files);

  for (const expected of [
    'index.html',
    'manifesto.txt',
    'legal-privacy.md',
    'legal-tos.md',
    'dfinity-bundle.js',
    'artists-nft-revenue-splits.webp',
    'games/infection/index.html',
    'games/infection/audio/death-loop.mp3',
    'games/infection/audio/gameplay-loop.mp3',
    'games/infection/audio/menu-loop.mp3',
    'games/swing-blade/index.html',
    'games/skate-apocalypse/index.html',
    'games/skate-apocalypse/game.js',
    'games/skate-apocalypse/styles.css',
  ]) {
    assert.ok(fileSet.has(expected), `publish payload missing ${expected}`);
  }

  const forbiddenPrefixes = [
    'backend/',
    'docs/',
    'scripts/',
    'tasks/',
    '.openclaw-review/',
    '.git/',
    '.deploy/',
  ];
  const forbiddenFiles = [
    'CANONICAL.md',
    'PROJECT.md',
    'PROJECT_ROOT_STRUCTURE.md',
    'README_CANONICAL_DEPLOY.md',
    'ROLLBACK.md',
    'deploy-manifest.json',
    '.deployignore',
    '.gitignore',
  ];

  for (const file of files) {
    assert.equal(file, file.replaceAll('\\\\', '/'), `manifest path should use forward slashes: ${file}`);
    assert.ok(!forbiddenPrefixes.some((prefix) => file.startsWith(prefix)), `forbidden internal path copied: ${file}`);
    assert.ok(!forbiddenFiles.includes(file), `forbidden internal file copied: ${file}`);
  }

  const manifest = readFileSync(join(outDir, 'deploy-manifest.txt'), 'utf8').trim().split(/\r?\n/);
  assert.deepEqual(manifest, files, 'deploy-manifest.txt must list the exact sorted payload');
  assert.deepEqual(files, [...files].sort(), 'publish payload should be deterministic/sorted');
} finally {
  rmSync(outDir, { recursive: true, force: true });
}

function listFiles(dir) {
  const output = [];
  walk(dir);
  return output.sort();

  function walk(current) {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const full = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.isFile()) continue;
      const rel = relative(dir, full).split(sep).join('/');
      output.push(rel);
      assert.ok(statSync(full).size > 0, `copied file is empty: ${rel}`);
    }
  }
}
