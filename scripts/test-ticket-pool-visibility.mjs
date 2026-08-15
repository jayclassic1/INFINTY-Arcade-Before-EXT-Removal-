import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const match = html.match(/async function openGameDetails\(id\)\{[\s\S]*?\n\}/);
if (!match) throw new Error('openGameDetails function not found');
const openGameDetailsSource = match[0];

function createHarness({ isAdminUser = false, sub }) {
  const appended = [];
  const existing = { remove() {} };

  const context = {
    console,
    S: { connected: true, quarters: 42, principalText: 'aaaaa-aa' },
    document: {
      body: { appendChild(node) { appended.push(node); } },
      createElement() {
        return {
          className: '',
          id: '',
          _innerHTML: '',
          set innerHTML(value) { this._innerHTML = value; },
          get innerHTML() { return this._innerHTML; },
        };
      },
      getElementById(id) { return id === 'm-backroom-game' ? existing : null; },
    },
    showConnect() { throw new Error('should not request connect'); },
    getSubmissions() { return [sub]; },
    hideGameChrome() {},
    getBackendActor: async () => ({
      getGameBackedTicketPool: async () => 12345n,
      getGameRawTicketPool: async () => 67890n,
    }),
    getGameBackedTicketPoolForDisplay: async (be, gameId) => Number(await be.getGameBackedTicketPool(gameId)),
    getGameRawTicketPoolForAdmin: async (be, gameId) => Number(await be.getGameRawTicketPool(gameId)),
    getGameHighScoreForDisplay: async () => ({ score: 9999 }),
    getGameInputType: () => 'standard',
    normalizeGamePayoutConfig: value => value,
    payoutDomId: value => String(value).replace(/[^a-zA-Z0-9_-]/g, '_'),
    renderCompactGameStats: () => '',
    renderPayoutLadder: () => '',
    approvalButtons: () => '',
    isAdmin: () => isAdminUser,
    galleryNav() {},
    galleryGoTo() {},
    closeGameModal() {},
    toggleInlineGameAdminTools() {},
    escHtml: value => String(value),
    JSON,
    Date,
    Number,
    Math,
    _currentGamePlaying: null,
  };

  vm.createContext(context);
  vm.runInContext(openGameDetailsSource, context);

  return {
    async render() {
      await context.openGameDetails(sub.id);
      assert.equal(appended.length, 1, 'modal should be appended once');
      return appended[0].innerHTML;
    },
  };
}

const ticketGame = {
  id: 'ticket-1',
  name: 'Ticket Game',
  dev: 'Dev',
  desc: 'Arcade desc',
  gameTier: 'showroom',
  paysTickets: true,
  thumb: 'thumb.png',
  screenshots: [],
};

const xpGame = {
  id: 'xp-1',
  name: 'XP Game',
  dev: 'Dev',
  desc: 'XP desc',
  gameTier: 'showroom',
  paysTickets: false,
  thumb: 'thumb.png',
  screenshots: [],
};

const regularHtml = await createHarness({ isAdminUser: false, sub: ticketGame }).render();
assert.match(regularHtml, /Backed Ticket Pool/i, 'regular users should see a backed-only ticket pool card for ticket games');
assert.match(regularHtml, /Currently backed for payouts: <b[^>]*>12,345 Tickets<\/b>/i, 'regular users should see the numeric backed ticket pool');
assert.doesNotMatch(regularHtml, /67,890/, 'regular users should not see the raw internal ticket pool counter');
assert.doesNotMatch(regularHtml, /Admin Audit/i, 'regular users should not see admin audit context');
assert.doesNotMatch(regularHtml, /Raw Pool/i, 'regular users should not see raw/internal counter labels');

const adminHtml = await createHarness({ isAdminUser: true, sub: ticketGame }).render();
assert.match(adminHtml, /Backed Ticket Pool/i, 'admins should still see the backed-only public framing');
assert.match(adminHtml, /Currently backed for payouts: <b[^>]*>12,345 Tickets<\/b>/i, 'admins should still see the public backed ticket pool');
assert.match(adminHtml, /Admin Audit/i, 'admins should see admin audit context in the same details view');
assert.match(adminHtml, /Raw Pool: 67,890 Tickets/i, 'admins should see raw/internal counter labeling separated from public framing');
assert.match(adminHtml, /Backed Pool: 12,345 Tickets/i, 'admins should see backed/admin audit labeling too');

const xpHtml = await createHarness({ isAdminUser: false, sub: xpGame }).render();
assert.doesNotMatch(xpHtml, /Ticket Pool/i, 'non-ticket games should not render ticket pool details');

console.log('ticket-pool-visibility tests passed');
