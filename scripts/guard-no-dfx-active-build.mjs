import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/^\/(.:\/)/, '$1');
const forbiddenDfx = /(^|[^A-Za-z0-9_./-])dfx(\.exe|\.cmd|\.ps1)?(\s|$)/i;
const bareWindowsIcpTools = /(^|&&|\|\||;)\s*(?:npm\s+exec\b[^&|;]*\b(?:icp|ic-wasm)\b|(?:icp|mops|ic-wasm)(?:\.exe|\.cmd|\.ps1)?\b)/i;
const activeScriptNames = /(?:build|deploy|predeploy|upgrade|install|canister|wasm|check|toolchain)/i;
const allowLegacyReference = new Set(['backend/dfx.json']);
const problems = [];

function rel(path) {
  return relative(root, path).replace(/\\/g, '/');
}

function checkDfx(path, label, text) {
  if (forbiddenDfx.test(text)) problems.push(`${label}: ${rel(path)}`);
}

const packagePath = join(root, 'package.json');
const pkg = JSON.parse(readFileSync(packagePath, 'utf8'));
for (const [name, command] of Object.entries(pkg.scripts ?? {})) {
  if (!activeScriptNames.test(name)) continue;
  if (forbiddenDfx.test(command)) problems.push(`package.json script ${name} invokes dfx`);
  if (bareWindowsIcpTools.test(command)) {
    problems.push(`package.json script ${name} bypasses scripts/run-icp-tool.mjs`);
  }
}

function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    const pathRel = rel(path);
    if (pathRel.startsWith('.git/') || pathRel.startsWith('.mops/') || pathRel.startsWith('backend/.dfx/') || pathRel.startsWith('backend/.build/') || pathRel.startsWith('.deploy/') || pathRel.startsWith('tasks/') || pathRel.includes('/node_modules/')) continue;
    const stats = statSync(path);
    if (stats.isDirectory()) {
      walk(path);
      continue;
    }
    if (!/\.(mjs|js|cjs|ps1|sh|bat|cmd|json|ya?ml)$/i.test(entry)) continue;
    if (allowLegacyReference.has(pathRel)) continue;
    if (pathRel === 'scripts/guard-no-dfx-active-build.mjs') continue;
    if (pathRel === 'package.json') continue;
    if (!activeScriptNames.test(entry) && !pathRel.startsWith('scripts/')) continue;
    checkDfx(path, 'active build/deploy script contains DFX command', readFileSync(path, 'utf8'));
  }
}

walk(root);

if (problems.length) {
  console.error('Active build/deploy guard failed. DFX is blocked; package ICP tools must route through scripts/run-icp-tool.mjs. Legacy backend/dfx.json may remain as reference only.');
  for (const problem of problems) console.error(`- ${problem}`);
  process.exit(1);
}

console.log('Active build/deploy guard passed: no dfx invocation and package ICP tools route through scripts/run-icp-tool.mjs.');
