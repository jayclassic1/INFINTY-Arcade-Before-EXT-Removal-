import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(process.cwd());
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const gameHtmlPath = path.join(root, 'games', 'skate-apocalypse', 'index.html');
const gameJsPath = path.join(root, 'games', 'skate-apocalypse', 'game.js');
const gameCssPath = path.join(root, 'games', 'skate-apocalypse', 'styles.css');

assert.doesNotMatch(html, /id='shredGnarLocalLauncher'/, 'Shred Gnar local launcher must not appear in Showroom');
assert.doesNotMatch(html, /LOCAL TEST PATH[\s\S]{0,500}Shred Gnar/, 'Showroom must not surface local Shred Gnar test path');
assert.ok(fs.existsSync(gameHtmlPath), 'missing standalone Shred Gnar page');
assert.ok(fs.existsSync(gameJsPath), 'missing standalone Shred Gnar game.js');
assert.ok(fs.existsSync(gameCssPath), 'missing standalone Shred Gnar styles.css');

const gameHtml = fs.readFileSync(gameHtmlPath, 'utf8');
assert.match(gameHtml, /Shred Gnar/, 'standalone Shred Gnar page should keep game title');

console.log('shred-gnar-standalone-page ok');
