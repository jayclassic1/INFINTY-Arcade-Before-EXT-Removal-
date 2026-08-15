#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

const rootIndex = readFileSync(join(process.cwd(), 'index.html'));
const deployIndex = readFileSync(join(process.cwd(), '.deploy', 'frontend-public', 'index.html'));

const hash = (buf) => createHash('sha256').update(buf).digest('hex');
const rootHash = hash(rootIndex);
const deployHash = hash(deployIndex);

console.log(`root index.html sha256: ${rootHash}`);
console.log(`deploy .deploy/frontend-public/index.html sha256: ${deployHash}`);

if (rootHash !== deployHash) {
  console.error('FAIL deploy artifact index.html is stale relative to reviewed root index.html');
  process.exit(1);
}

console.log('PASS deploy artifact index.html matches reviewed root index.html');
