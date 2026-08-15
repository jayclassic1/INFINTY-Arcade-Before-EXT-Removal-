#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const swingPath = join(root, 'games', 'swing-blade', 'index.html');
const parentPath = join(root, 'index.html');
const source = readFileSync(swingPath, 'utf8');
const parent = readFileSync(parentPath, 'utf8');

const checks = [];
function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
}

check('handles parent arcade-key messages', /case ['"]arcade-key['"]/.test(source) && /__swingBladeApplyArcadeKey/.test(source));
check('defines InputManager.applyArcadeAction', /applyArcadeAction\s*\(\s*action\s*,\s*state\s*\)/.test(source));

const requiredMappings = {
  left: 'ArrowLeft',
  right: 'ArrowRight',
  up: 'ArrowUp',
  down: 'ArrowDown',
  a: 'Space',
  start: 'Space',
  b: 'KeyC',
};
for (const [action, key] of Object.entries(requiredMappings)) {
  const pattern = new RegExp(`${action}\\s*:\\s*['\"]${key}['\"]`);
  check(`maps ${action} to ${key}`, pattern.test(source));
}

check(
  'sets justPressed only on transition from up to down',
  /if\s*\(\s*!this\.keys\[code\]\s*\)\s*{[\s\S]*?this\.justPressed\[code\]\s*=\s*true/.test(source)
);
check('supports down/up string states', /state\s*===\s*['"]down['"]/.test(source) && /state\s*===\s*['"]up['"]/.test(source));
check('supports boolean/number states safely', /state\s*===\s*true/.test(source) && /state\s*===\s*false/.test(source));
check('native keydown listener remains', /window\.addEventListener\(['"]keydown['"]\s*,\s*this\._onKeyDown\)/.test(source));
check('native keyup listener remains', /window\.addEventListener\(['"]keyup['"]\s*,\s*this\._onKeyUp\)/.test(source));
check('arcade-key events feed anti-cheat eventSink with source marker', /source\s*:\s*['"]arcade-key['"]/.test(source));
check('handles parent arcade-focus messages', /case ['"]arcade-focus['"]/.test(source) && /focusGameInput\(\)/.test(source));
check('canvas is focusable and focused on launch', /canvas\.setAttribute\(['"]tabindex['"]\s*,\s*['"]0['"]\)/.test(source) && /setTimeout\(focusGameInput\s*,\s*0\)/.test(source));
check('first click or touch requests parent iframe focus, attempts game input focus, and notifies interaction', /function\s+activateArcadeInput\(\)\s*{[\s\S]*?_initAudioOnce\(\);[\s\S]*?requestArcadeFocus\(\);[\s\S]*?focusGameInput\(\);[\s\S]*?notifyArcadeGameInteraction\(\);[\s\S]*?}/.test(source) && /document\.addEventListener\(['"]click['"]\s*,\s*activateArcadeInput/.test(source) && /document\.addEventListener\(['"]touchstart['"]\s*,\s*activateArcadeInput/.test(source));
check('game posts arcade-game-interaction once from first click or touch', /let\s+arcadeGameInteractionNotified\s*=\s*false/.test(source) && /function\s+notifyArcadeGameInteraction\(\)\s*{[\s\S]*?arcadeGameInteractionNotified\s*=\s*true[\s\S]*?postMessage\(\{\s*type\s*:\s*['"]arcade-game-interaction['"]\s*}/.test(source));
check('game posts arcade-input-ready after focus and apply hook readiness', /const\s+ready\s*=\s*document\.activeElement\s*===\s*target/.test(source) && /notifyArcadeInputReady\(['"]focus-ready['"]\)/.test(source) && /notifyArcadeInputReady\(['"]apply-hook-ready['"]\)/.test(source));
check('game can request parent focus without claiming ready', /function\s+requestArcadeFocus\(\)\s*{[\s\S]*?postMessage\(\{\s*type\s*:\s*['"]arcade-focus-request['"]\s*}/.test(source));

check('parent defines Space fallback bridge to P1-A', /ARCADE_NATIVE_KEY_FALLBACKS\s*=\s*{\s*Space\s*:\s*{\s*player\s*:\s*['"]p1['"]\s*,\s*action\s*:\s*['"]a['"]\s*}\s*}/.test(parent));
check('parent normalizes saved keymap against defaults', /function\s+getKeyMap\(\)\s*{[\s\S]*?JSON\.parse\(JSON\.stringify\(DEFAULT_KEY_MAP\)\)[\s\S]*?const\s+normalized=\{p1:\{\.\.\.defaults\.p1\},p2:\{\.\.\.defaults\.p2\}\}[\s\S]*?return\s+normalized;[\s\S]*?}/.test(parent));
check('parent Space fallback is not suppressed by unrelated custom mappings', /let\s+nativeFallbackAlreadySent\s*=\s*false/.test(parent) && /if\(fallback&&player===fallback\.player&&action===fallback\.action\)\s*nativeFallbackAlreadySent=true/.test(parent) && /if\s*\(\s*fallback\s*&&\s*!nativeFallbackAlreadySent\s*\)/.test(parent));
check('parent defines shell keyboard focus authority helper', /function\s+ensureGameShellKeyboardFocus\(\)\s*{[\s\S]*?m-backroom-game[\s\S]*?setAttribute\(['"]tabindex['"]\s*,\s*['"]-1['"]\)[\s\S]*?\.focus\(/.test(parent));
check('parent handles current-iframe focus requests by focusing iframe', /msgType\s*===\s*['"]arcade-focus-request['"]/.test(parent) && /iframe&&event\.source===iframe\.contentWindow\)\s*{[\s\S]*?ensureGameIframeFocus\(\)/.test(parent));
check('parent handles first game interaction by preserving iframe keyboard focus', /msgType\s*===\s*['"]arcade-game-interaction['"]/.test(parent) && /iframe&&event\.source===iframe\.contentWindow\)\s*{[\s\S]*?ensureGameIframeFocus\(\)/.test(parent));
check('parent still accepts arcade-input-ready only from current iframe and flushes queued keys', /msgType\s*===\s*['"]arcade-input-ready['"]/.test(parent) && /iframe&&event\.source===iframe\.contentWindow\)\s*{[\s\S]*?arcadeGameInputReady=true[\s\S]*?flushPendingArcadeKeyEvents\(\)/.test(parent));
check('parent defines dismissGameFocusOverlay helper for stale overlays', /function\s+dismissGameFocusOverlay\s*\(\s*\)/.test(parent));
check('focus hint overlay is removed from game launch path', !/mountGameFocusOverlay\s*\(/.test(parent) && !/Click Game to activate keyboard/.test(parent) && !/gameFocusOverlay/.test(parent.replace(/function\s+dismissGameFocusOverlay\s*\(\s*\)\s*\{[\s\S]*?\n\}/, '')));
check('game launch preserves iframe keyboard focus', /setTimeout\s*\(\s*\(\)\s*=>\s*{\s*ensureGameIframeFocus\(\);\s*}\s*,\s*300\s*\)/.test(parent) && /setTimeout\s*\(\s*\(\)\s*=>\s*{\s*ensureGameIframeFocus\(\);\s*}\s*,\s*900\s*\)/.test(parent));
check('diagnostic route logs parent-to-iframe input path when enabled', /function\s+arcadeInputDebug\(stage,detail=\{\}\)/.test(parent) && /msgType\s*===\s*['"]arcade-input-debug['"]/.test(parent) && /parent-post-arcade-key/.test(parent));
check('parent queues first Space until iframe input is ready', /let\s+arcadeGameInputReady\s*=\s*false/.test(parent) && /function\s+postOrQueueArcadeKeyToGame\(iframe,msg\)/.test(parent) && /parent-queue-arcade-key/.test(parent) && /parent-replay-arcade-key/.test(parent) && /resetArcadeInputReadiness\(['"]insert-coin-iframe-load['"]\)/.test(parent));
check('game reports iframe receive, apply wrapper, and Space justPressed diagnostics', /function\s+swingBladeInputDebug\(stage,\s*detail\s*=\s*\{\}\)/.test(source) && /iframe-received-arcade-key/.test(source) && /apply-wrapper-result/.test(source) && /apply-arcade-action-space-just-pressed/.test(source));
check('parent uses capture-phase keyboard forwarding and duplicate-event guard', /document\.addEventListener\(['"]keydown['"]\s*,\s*\(e\)=>\{forwardArcadeKeyToGame\(e,['"]down['"]\);\}\s*,\s*\{capture:true\}\)/.test(parent) && /document\.addEventListener\(['"]keyup['"]\s*,\s*\(e\)=>\{forwardArcadeKeyToGame\(e,['"]up['"]\);\}\s*,\s*\{capture:true\}\)/.test(parent) && /__arcadeForwardedToGame/.test(parent));
check('parent forwarding avoids text-entry targets', /target\.isContentEditable/.test(parent) && /\['input','textarea','select'\]\.includes\(tag\)/.test(parent));

const forbiddenBackendCalls = [
  'getBackendActor',
  'submitGameScore',
  'spendTokensOnGame',
  'claimRoyalties',
  'endGameSession',
  'Principal.fromText',
  'backendActor',
  'canister',
];
for (const forbidden of forbiddenBackendCalls) {
  check(`does not add backend/canister call token: ${forbidden}`, !source.includes(forbidden));
}

const failed = checks.filter(c => !c.pass);
for (const c of checks) {
  const mark = c.pass ? 'PASS' : 'FAIL';
  console.log(`${mark} ${c.name}${c.detail ? ` - ${c.detail}` : ''}`);
}

if (failed.length) {
  console.error(`\nvalidate-swing-blade-input-bridge: FAIL (${failed.length}/${checks.length} checks failed)`);
  process.exit(1);
}

console.log(`\nvalidate-swing-blade-input-bridge: PASS (${checks.length}/${checks.length} checks passed)`);
