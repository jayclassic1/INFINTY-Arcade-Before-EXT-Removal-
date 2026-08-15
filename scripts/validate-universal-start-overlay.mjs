import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const frontendPath = path.join(root, 'index.html');
const frontend = fs.readFileSync(frontendPath, 'utf8');

function sliceBetween(source, startNeedle, endNeedle) {
  const start = source.indexOf(startNeedle);
  assert.ok(start >= 0, startNeedle + ' should be present');
  const end = source.indexOf(endNeedle, start);
  assert.ok(end > start, endNeedle + ' should follow ' + startNeedle);
  return source.slice(start, end);
}

assert.match(
  frontend,
  /const ARCADE_GAME_START_VERSION='universal-start-20260520';/,
  'frontend should define a stable universal Start cache-bust version',
);

assert.match(
  frontend,
  /function arcadeVersionedGameUrl\(url\)[\s\S]*searchParams\.set\('arcadeStartVersion',ARCADE_GAME_START_VERSION\)/,
  'frontend should append arcadeStartVersion to eligible game iframe URLs',
);

assert.match(
  frontend,
  /<button id='arcadeStartOverlay'[^>]*>Start<\/button>/,
  'game modal should contain the universal Start overlay button',
);

assert.match(
  frontend,
  /id='arcadeStartOverlay'[^>]*position:absolute;top:12px;right:12px;/,
  'Start overlay should be positioned top-right in the gameplay area',
);

assert.match(
  frontend,
  /function activateArcadeStartOverlay\(\)[\s\S]*ensureGameIframeFocus\(\);[\s\S]*postArcadeStartAction\(iframe,'a','down'\);[\s\S]*postArcadeStartAction\(iframe,'a','up'\);[\s\S]*postArcadeStartAction\(iframe,'start','down'\);[\s\S]*postArcadeStartAction\(iframe,'start','up'\);[\s\S]*type:'arcade-start'/,
  'Start overlay click should focus iframe and send a/start down/up plus arcade-start',
);

const insertCoin = sliceBetween(frontend, 'async function insertCoin(id){', '// === BUY GAME');
assert.match(
  insertCoin,
  /resetArcadeStartOverlay\('insert-coin-iframe-load'\);[\s\S]*src='\$\{arcadeVersionedGameUrl\(sub\.url\)\}'/,
  'paid session iframe load should reset Start overlay and use versioned URL',
);

const demo = sliceBetween(frontend, 'async function tryGameDemo(id){', '// Demo timer overlay');
assert.match(
  demo,
  /resetArcadeStartOverlay\('demo-iframe-load'\);[\s\S]*src='\$\{arcadeVersionedGameUrl\(sub\.url\)\}'/,
  'demo iframe load should reset Start overlay and use versioned URL',
);

assert.match(
  frontend,
  /if\(msgType==='arcade-game-interaction'\)[\s\S]*hideArcadeStartOverlay\('game-interaction'\)/,
  'Start overlay should hide when the game reports interaction',
);

assert.match(
  frontend,
  /if\(msgType==='arcade-input-ready'\)[\s\S]*hideArcadeStartOverlay\('input-ready'\)/,
  'Start overlay should hide when the game reports input readiness',
);

assert.match(
  frontend,
  /if\(msgType==='arcade-latest-score'\)[\s\S]*hideArcadeStartOverlay\('latest-score'\)/,
  'Start overlay should hide when score/game-over arrives',
);

assert.match(
  frontend,
  /function closeGameModalImmediate\(\)[\s\S]*hideArcadeStartOverlay\('modal-close'\)/,
  'Start overlay should hide on modal close',
);

console.log('validate-universal-start-overlay: PASS');
