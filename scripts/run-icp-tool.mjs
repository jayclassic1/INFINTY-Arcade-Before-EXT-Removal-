import { spawnSync } from 'node:child_process';
import { cwd, exit, platform } from 'node:process';

const allowedTools = new Set(['icp', 'mops', 'ic-wasm']);
const wslToolPath = [
  '$HOME/.local/node/current/bin',
  '$HOME/.cargo/bin',
  '/usr/local/sbin',
  '/usr/local/bin',
  '/usr/sbin',
  '/usr/bin',
  '/sbin',
  '/bin',
].join(':');
const [tool, ...toolArgs] = process.argv.slice(2);

if (!tool || !allowedTools.has(tool)) {
  console.error(`Usage: node scripts/run-icp-tool.mjs <${[...allowedTools].join('|')}> [...args]`);
  exit(2);
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
}

function toWslPath(winPath) {
  const match = String(winPath).match(/^([A-Za-z]):\\(.*)$/);
  if (!match) {
    console.error(`Failed to convert Windows path for WSL: ${winPath}`);
    exit(1);
  }
  const drive = match[1].toLowerCase();
  const rest = match[2].replace(/\\/g, '/');
  return `/mnt/${drive}/${rest}`;
}

let command;
let commandArgs;

if (platform === 'win32') {
  const wslCwd = toWslPath(cwd());
  command = 'wsl.exe';
  commandArgs = [
    'bash',
    '-lc',
    [
      'set -e',
      `export PATH=${shellQuote(wslToolPath)}`,
      `cd ${shellQuote(wslCwd)}`,
      `if ! command -v ${shellQuote(tool)} >/dev/null 2>&1; then echo ${shellQuote(`${tool} is not installed in the approved WSL ICP tooling PATH.`)} >&2; exit 127; fi`,
      `exec ${shellQuote(tool)} ${toolArgs.map(shellQuote).join(' ')}`,
    ].join('\n'),
  ];
} else {
  command = tool;
  commandArgs = toolArgs;
}

const result = spawnSync(command, commandArgs, {
  stdio: 'inherit',
  shell: false,
});

if (result.error) {
  console.error(result.error.message);
  exit(1);
}

exit(result.status ?? 0);
