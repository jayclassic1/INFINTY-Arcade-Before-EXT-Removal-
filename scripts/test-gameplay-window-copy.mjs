import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const frontendRoot = path.resolve(scriptDir, '..');
const html = fs.readFileSync(path.join(frontendRoot, 'index.html'), 'utf8');

const start = html.indexOf('async function openBackroomGame(id)');
assert.notEqual(start, -1, 'openBackroomGame function should exist');
const end = html.indexOf('// Details page - opened via DETAILS button on game cards', start);
assert.notEqual(end, -1, 'openBackroomGame section should end before details page');
const openGameSource = html.slice(start, end);

assert.match(openGameSource, /INSERT TOKEN/, 'gameplay window should say INSERT TOKEN');
assert.doesNotMatch(openGameSource, /INSERT COIN/, 'gameplay window should not say INSERT COIN');
assert.match(openGameSource, />Submit Score<\/button>/, 'top-right gameplay action should be Submit Score');
assert.doesNotMatch(openGameSource, /Submit Score & Close<\/button>/, 'Submit Score button should not include & Close');
assert.match(openGameSource, />Close<\/button>/, 'secondary gameplay close action should be Close');
assert.doesNotMatch(openGameSource, />Force Close<\/button>/, 'Force Close button label should not be visible');
assert.doesNotMatch(openGameSource, /Leave Game/i, 'gameplay window should not expose Leave Game');
assert.doesNotMatch(openGameSource, /renderPayoutLadder|PAYOUT_TABLE|10,000|10000|500 Tickets|250 Tickets|100 Tickets|40 Tickets|15 Tickets|5 Tickets/i, 'gameplay coin gate should not render payout ladder visuals');
assert.match(openGameSource, /per session &gt; Submitting Score ends session/, 'gameplay session helper should explain submitting score ends the session');
assert.doesNotMatch(openGameSource, /Submit Score to end session|Best score counts|Cumulative score/, 'gameplay session helper should not show stale scoring-mode or old helper copy');

console.log('gameplay window copy tests passed');
