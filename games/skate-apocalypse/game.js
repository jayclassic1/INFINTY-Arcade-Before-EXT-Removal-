const HOLD_POP_WINDOW_SECONDS = 0.22;
const GRAVITY = 1700;
const HELD_GRAVITY = 930;
const HORIZONTAL_ACCEL = 440;
const HORIZONTAL_DRAG = 4.2;
const AUTO_PUSH = 240;
const MIN_SPEED = 160;
const MAX_SPEED = 420;
const LANDING_BAIL_SPEED = 940;
const SCORE_RATE = 18;
const BASE_WIDTH = 960;
const BASE_HEIGHT = 540;
const GROUND_MARGIN = 92;

export function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function formatScore(score) {
  return Math.floor(score).toString().padStart(6, '0');
}

function formatCombo(combo) {
  return `x${combo.toFixed(1)}`;
}

function formatSpeed(speed) {
  return `${Math.round(speed / 9.5)} mph`;
}

function getGroundY(viewHeight) {
  return viewHeight - GROUND_MARGIN;
}

export function createInitialState({ width = BASE_WIDTH, height = BASE_HEIGHT } = {}) {
  const groundY = getGroundY(height);

  return {
    running: true,
    runState: 'running',
    lastFrameTime: 0,
    elapsedMs: 0,
    groundOffset: 0,
    message: 'Shred Gnar online',
    forwardSpeed: 246,
    palette: {
      skyTop: '#202733',
      skyBottom: '#07090d',
      haze: 'rgba(255, 142, 61, 0.08)',
      skyline: '#161b26',
      skylineFar: '#0f131c',
      ground: '#1f262e',
      groundLine: '#ff8d3a',
      groundDetail: '#aa6938',
    },
    score: {
      total: 0,
      combo: 1,
      comboMeter: 0,
      frozen: false,
    },
    player: {
      width: 40,
      height: 64,
      x: width * 0.22,
      y: groundY,
      velocityX: 0,
      velocityY: 0,
      color: '#f1eee8',
      onGround: true,
      grinding: false,
      bailed: false,
      facing: 1,
      jumpHoldTime: 0,
      jumpQueued: false,
      holdReleased: true,
      popBonusReady: false,
    },
    input: {
      left: false,
      right: false,
      jumpHeld: false,
      restartPressed: false,
    },
  };
}

export function pressJump(state) {
  if (state.player.bailed) {
    state.input.restartPressed = true;
    return;
  }

  state.input.jumpHeld = true;

  if (state.player.onGround) {
    state.player.velocityY = -620;
    state.player.onGround = false;
    state.player.jumpHoldTime = 0;
    state.player.holdReleased = false;
    state.player.popBonusReady = true;
    state.message = 'Pop!';
    return;
  }

  state.player.jumpQueued = true;
}

export function releaseJump(state) {
  state.input.jumpHeld = false;

  if (!state.player.onGround && !state.player.holdReleased) {
    const holdRatio = clamp(state.player.jumpHoldTime / HOLD_POP_WINDOW_SECONDS, 0, 1);
    const bonus = 80 + holdRatio * 170;
    state.player.velocityY -= bonus;
    state.player.holdReleased = true;
    state.player.popBonusReady = false;
    state.message = holdRatio > 0.45 ? 'Late pop boost' : 'Quick release';
  }
}

export function triggerBail(state, reason = 'Bailed out') {
  state.runState = 'bailed';
  state.player.bailed = true;
  state.player.grinding = false;
  state.player.onGround = true;
  state.player.velocityX = 0;
  state.player.velocityY = 0;
  state.score.frozen = true;
  state.score.combo = 1;
  state.score.comboMeter = 0;
  state.message = reason;
}

export function restartRun(state, { width = BASE_WIDTH, height = BASE_HEIGHT } = {}) {
  const fresh = createInitialState({ width, height });
  Object.assign(state, fresh);
  state.message = 'Drop back in';
}

export function updateSimulation(state, deltaSeconds, { width = BASE_WIDTH, height = BASE_HEIGHT } = {}) {
  if (state.runState === 'bailed') {
    if (state.input.restartPressed) {
      restartRun(state, { width, height });
      state.input.restartPressed = false;
    }
    return state;
  }

  const player = state.player;
  const input = state.input;
  const groundY = getGroundY(height);

  state.elapsedMs += deltaSeconds * 1000;

  const directionalInfluence = (input.right ? 1 : 0) - (input.left ? 1 : 0);
  const autoPushTarget = AUTO_PUSH + directionalInfluence * 42;
  state.forwardSpeed += (autoPushTarget - state.forwardSpeed) * Math.min(1, deltaSeconds * 1.8);
  state.forwardSpeed = clamp(state.forwardSpeed, MIN_SPEED, MAX_SPEED);
  state.groundOffset = (state.groundOffset + state.forwardSpeed * deltaSeconds) % 96;

  if (player.onGround) {
    player.velocityX += directionalInfluence * HORIZONTAL_ACCEL * deltaSeconds;
    player.velocityX *= Math.max(0, 1 - HORIZONTAL_DRAG * deltaSeconds);
  } else {
    player.velocityX += directionalInfluence * HORIZONTAL_ACCEL * 0.35 * deltaSeconds;
    if (input.jumpHeld && !player.holdReleased) {
      player.jumpHoldTime += deltaSeconds;
      if (player.jumpHoldTime >= HOLD_POP_WINDOW_SECONDS) {
        player.holdReleased = true;
        player.popBonusReady = false;
      }
    }

    const gravityNow = input.jumpHeld && !player.holdReleased ? HELD_GRAVITY : GRAVITY;
    player.velocityY += gravityNow * deltaSeconds;
  }

  player.x += player.velocityX * deltaSeconds;
  player.y += player.velocityY * deltaSeconds;
  player.x = clamp(player.x, width * 0.14, width * 0.48);

  if (!player.onGround && player.y >= groundY) {
    player.y = groundY;
    const landingVelocity = player.velocityY;
    player.velocityY = 0;
    player.onGround = true;
    player.jumpHoldTime = 0;
    player.holdReleased = true;
    player.popBonusReady = false;

    if (landingVelocity > LANDING_BAIL_SPEED) {
      triggerBail(state, 'Bail: heavy slam');
      return state;
    }

    state.message = landingVelocity > 630 ? 'Sketchy landing' : 'Clean landing';
    state.score.comboMeter += landingVelocity > 630 ? 0.15 : 0.35;
    state.score.combo = clamp(1 + state.score.comboMeter, 1, 12);
  }

  if (!state.score.frozen) {
    const paceBonus = state.forwardSpeed / 240;
    state.score.total += SCORE_RATE * paceBonus * state.score.combo * deltaSeconds;
  }

  if (player.onGround && player.jumpQueued) {
    player.jumpQueued = false;
    pressJump(state);
  }

  return state;
}

function drawBackground(context, state, width, height) {
  const gradient = context.createLinearGradient(0, 0, 0, height);
  gradient.addColorStop(0, state.palette.skyTop);
  gradient.addColorStop(1, state.palette.skyBottom);
  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  context.fillStyle = state.palette.haze;
  context.fillRect(0, 0, width, height);

  context.fillStyle = state.palette.skylineFar;
  context.fillRect(0, height - 210, width, 78);
  context.fillStyle = state.palette.skyline;
  context.fillRect(0, height - 164, width, 54);
}

function drawGround(context, state, width, height) {
  const groundTop = getGroundY(height);
  context.fillStyle = state.palette.ground;
  context.fillRect(0, groundTop, width, height - groundTop);

  context.fillStyle = state.palette.groundLine;
  context.fillRect(0, groundTop, width, 4);

  context.strokeStyle = state.palette.groundDetail;
  context.lineWidth = 2;
  for (let x = -state.groundOffset; x < width + 96; x += 48) {
    context.beginPath();
    context.moveTo(x, groundTop + 20);
    context.lineTo(x + 22, groundTop + 10);
    context.lineTo(x + 46, groundTop + 22);
    context.stroke();
  }
}

function drawPlayer(context, state) {
  const { player } = state;
  context.fillStyle = player.color;
  context.fillRect(player.x, player.y - player.height, player.width, player.height);

  context.fillStyle = player.bailed ? '#ff6673' : '#ff8d3a';
  context.fillRect(player.x - 8, player.y - 6, player.width + 20, 6);

  if (!player.onGround) {
    context.strokeStyle = 'rgba(249, 203, 86, 0.8)';
    context.lineWidth = 2;
    context.beginPath();
    context.arc(player.x + player.width * 0.5, player.y - player.height - 8, 10 + player.jumpHoldTime * 18, 0, Math.PI * 2);
    context.stroke();
  }
}

function syncHud(state, elements) {
  elements.score.textContent = formatScore(state.score.total);
  elements.combo.textContent = formatCombo(state.score.combo);
  elements.speed.textContent = formatSpeed(state.forwardSpeed);
  elements.trick.textContent = state.message;
  elements.failTitle.textContent = state.player.bailed ? 'Bailed out' : 'Run stable';
  elements.failCopy.textContent = state.player.bailed
    ? 'Score growth is frozen. Press Space or R to restart your Shred Gnar run.'
    : 'Stay loose and keep the line alive.';
  elements.failPanel.classList.toggle('is-visible', state.player.bailed);
}

function attachBrowserGame() {
  const canvas = document.getElementById('gameCanvas');
  if (!(canvas instanceof HTMLCanvasElement)) {
    throw new Error('Shred Gnar boot failed: #gameCanvas was not found.');
  }

  const context = canvas.getContext('2d');
  if (!context) {
    throw new Error('Shred Gnar boot failed: 2D canvas context unavailable.');
  }

  const state = createInitialState();
  const elements = {
    score: document.getElementById('scoreValue'),
    combo: document.getElementById('comboValue'),
    speed: document.getElementById('speedValue'),
    trick: document.getElementById('trickValue'),
    failPanel: document.getElementById('failPanel'),
    failTitle: document.getElementById('failTitle'),
    failCopy: document.getElementById('failCopy'),
  };

  function getViewport() {
    return {
      width: canvas.clientWidth || BASE_WIDTH,
      height: canvas.clientHeight || BASE_HEIGHT,
    };
  }

  function resizeCanvas() {
    const ratio = window.devicePixelRatio || 1;
    const { width, height } = getViewport();
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.scale(ratio, ratio);

    if (state.player.onGround || state.player.bailed) {
      state.player.y = getGroundY(height);
    }
  }

  function render() {
    const { width, height } = getViewport();
    context.clearRect(0, 0, width, height);
    drawBackground(context, state, width, height);
    drawGround(context, state, width, height);
    drawPlayer(context, state);
    syncHud(state, elements);
  }

  function frame(timestamp) {
    if (!state.running) return;
    if (!state.lastFrameTime) state.lastFrameTime = timestamp;
    const deltaSeconds = Math.min((timestamp - state.lastFrameTime) / 1000, 0.05);
    state.lastFrameTime = timestamp;

    const viewport = getViewport();
    updateSimulation(state, deltaSeconds, viewport);
    render();
    window.requestAnimationFrame(frame);
  }

  window.addEventListener('keydown', (event) => {
    if (event.repeat) return;

    if (event.code === 'ArrowLeft') state.input.left = true;
    if (event.code === 'ArrowRight') state.input.right = true;
    if (event.code === 'Space') {
      event.preventDefault();
      if (state.player.bailed) {
        state.input.restartPressed = true;
      } else {
        pressJump(state);
      }
    }
    if (event.code === 'KeyR' && state.player.bailed) {
      state.input.restartPressed = true;
    }
  });

  window.addEventListener('keyup', (event) => {
    if (event.code === 'ArrowLeft') state.input.left = false;
    if (event.code === 'ArrowRight') state.input.right = false;
    if (event.code === 'Space') {
      event.preventDefault();
      releaseJump(state);
    }
  });

  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();
  render();
  window.requestAnimationFrame(frame);

  window.shredGnar = {
    state,
    bail(reason = 'Manual bail') {
      triggerBail(state, reason);
      render();
    },
    restart() {
      state.input.restartPressed = true;
      updateSimulation(state, 0, getViewport());
      render();
    },
  };
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  attachBrowserGame();
}
