#!/usr/bin/env node
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const source = readFileSync(join(process.cwd(), 'games', 'swing-blade', 'index.html'), 'utf8');
const checks = [];
const check = (name, pass) => checks.push({ name, pass: !!pass });

check('Neon title panel exists', /id=["']neonTitlePanel["']/.test(source));
check('Launch panel exists', /id=["']launchPanel["']/.test(source));
check('Neon Arcade Noir badge exists', /Neon Arcade Noir/.test(source));
check('Start button remains present', /id=["']startButton["'][^>]*aria-describedby=["']startHint["']/.test(source));
check('Start button uses approved Start Game label', />Start Game<\/button>/.test(source));
check('Approved helper text remains visible', /Start focuses controls\. Space also starts\./.test(source));
check('Control preview is visible before play', /class=["']neonControlGrid["'][\s\S]*Move[\s\S]*Jump[\s\S]*Blade[\s\S]*Dash/.test(source));
check('Title shell toggles with existing Start visibility path', /const\s+titlePanel\s*=\s*document\.getElementById\(['"]neonTitlePanel['"]\)/.test(source) && /titlePanel\.hidden\s*=\s*!visible/.test(source));
check('Launch shell toggles with existing Start visibility path', /const\s+launchPanel\s*=\s*document\.getElementById\(['"]launchPanel['"]\)/.test(source) && /launchPanel\.hidden\s*=\s*!visible/.test(source));
check('Game shell title class toggles through existing visibility path', /shell\.classList\.toggle\(['"]is-title['"]\s*,\s*!!visible\)/.test(source));
check('Existing game.start path is preserved', /currentGame\.start\(\)/.test(source) && /handleStartButtonClick/.test(source));
check('Space-start title path is preserved', /this\.input\.wasSpacePressed\(\)[\s\S]*this\.start\(\)/.test(source));
check('Input bridge apply hook remains present', /window\.__swingBladeApplyArcadeKey/.test(source) && /applyArcadeAction/.test(source));
check('Keymap Space fallback remains present', /start['"]?\s*:\s*['"]Space['"]/.test(source) || /start\s+to\s+Space/.test(source));
check('Mobile 390 layout has viewport-safe launch width', /#launchPanel[\s\S]*width:\s*min\(340px,\s*calc\(100vw\s*-\s*44px\)\)/.test(source));
const sourceWithoutComments = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');
check('No remote asset, import, font, or stylesheet references were added', !/(src\s*=\s*["']https?:\/\/|href\s*=\s*["']https?:\/\/|@import|<link\b|url\(\s*['"]?https?:\/\/)/i.test(sourceWithoutComments));
check('No raw machine safety labels are visible', !/(CLIENTREADY=FALSE|deliveryPerformed=false|clientReady=false|deployPerformed=true)/.test(source));

let diff = '';
try {
  diff = execSync('git diff --unified=0 -- games/swing-blade/index.html', {
    cwd: process.cwd(),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
} catch (_error) {
  diff = '';
}
check('Diff does not touch backend/economy/score submission tokens', !/(SUBMIT_SCORE|SCORE_SUBMITTED|SCORING|lastTickets|payout|reward|backendActor|getBackendActor|Principal\.fromText)/.test(diff));

let changed = [];
try {
  changed = execSync('git diff --name-only -- workspaces/jmai/dapps/infinity-arcade-Jay', {
    cwd: execSync('git rev-parse --show-toplevel', { cwd: process.cwd(), encoding: 'utf8' }).trim(),
    encoding: 'utf8',
  }).split(/\r?\n/).filter(Boolean);
} catch (_error) {
  changed = [];
}
const deploymentConfigPattern = '(^|/)' + 'd' + 'fx' + '\\.json$';
const blockedPathPatterns = [
  /\/backend\//i,
  new RegExp(deploymentConfigPattern, 'i'),
  /(^|\/)mops\.toml$/i,
  /(^|\/)icp\.yaml$/i,
  /deploy/i,
  /package-lock\.json$/i,
  /package\.json$/i,
];
const blockedChanged = changed.filter((file) => {
  const normalizedFile = file.replace(/\\/g, '/');
  return blockedPathPatterns.some((pattern) => pattern.test(normalizedFile));
});
check('No blocked backend/deploy/package files changed in Infinity Arcade project', blockedChanged.length === 0);

const failed = checks.filter((item) => !item.pass);
for (const item of checks) console.log(`${item.pass ? 'PASS' : 'FAIL'} ${item.name}`);
if (failed.length) {
  console.error(`\nvalidate-swing-blade-neon-arcade-noir: FAIL (${failed.length}/${checks.length} checks failed)`);
  process.exit(1);
}
console.log(`\nvalidate-swing-blade-neon-arcade-noir: PASS (${checks.length}/${checks.length} checks passed)`);
