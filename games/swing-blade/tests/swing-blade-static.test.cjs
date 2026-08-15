const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const gamePath = path.resolve(__dirname, '..', 'index.html');
const html = fs.readFileSync(gamePath, 'utf8');
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(match => match[1]);
assert(scripts.length > 0, 'index.html should contain an inline game script');
const gameScript = scripts.join('\n');

assert.doesNotThrow(() => new vm.Script(gameScript), 'inline Swing Blade script should parse as JavaScript');

const cloudSpawn = gameScript.match(/const cloudY = Math\.max\(18, platY - this\.rng\.nextInt\((\d+),\s*(\d+)\)\);/);
assert(cloudSpawn, 'cloud spawn height expression should be explicit and statically checkable');
assert(Number(cloudSpawn[1]) >= 110, 'clouds should spawn noticeably higher than before (minimum offset >= 110px)');
assert(Number(cloudSpawn[2]) >= 170, 'clouds should retain a high ceiling range (maximum offset >= 170px)');

const updateMatch = gameScript.match(/class AngelEnemy \{[\s\S]*?\n  update\(dt, player\) \{([\s\S]*?)\n  getBladeHitbox\(\)/);
assert(updateMatch, 'AngelEnemy.update should be present');
const updateBody = updateMatch[1];
assert(/if \(onCloud\) \{\s*this\.activateNear\(player\);\s*\}/.test(updateBody), 'angel should activate when the player lands on a cloud');
assert(!/if \(!onCloud\) \{[\s\S]*?this\.active = false[\s\S]*?return;[\s\S]*?\}/.test(updateBody), 'angel should not deactivate merely because the player left the cloud');
assert(/if \(!this\.active\) return;/.test(updateBody), 'inactive angel should remain idle until first cloud landing');

console.log('Swing Blade static checks passed');
