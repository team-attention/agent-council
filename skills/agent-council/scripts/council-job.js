#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const SCRIPT_DIR = __dirname;
const SKILL_DIR = path.resolve(SCRIPT_DIR, '..');
const WORKER_PATH = path.join(SCRIPT_DIR, 'council-job-worker.js');

const SKILL_CONFIG_FILE = path.join(SKILL_DIR, 'council.config.yaml');
const REPO_CONFIG_FILE = path.join(path.resolve(SKILL_DIR, '../..'), 'council.config.yaml');

function exitWithError(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function resolveDefaultConfigFile() {
  if (fs.existsSync(SKILL_CONFIG_FILE)) return SKILL_CONFIG_FILE;
  if (fs.existsSync(REPO_CONFIG_FILE)) return REPO_CONFIG_FILE;
  return SKILL_CONFIG_FILE;
}

function detectHostRole() {
  const normalized = SKILL_DIR.replace(/\\/g, '/');
  if (normalized.includes('/.claude/skills/')) return 'claude';
  if (normalized.includes('/.codex/skills/')) return 'codex';
  return 'unknown';
}

function normalizeBool(value) {
  if (value == null) return null;
  const v = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(v)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(v)) return false;
  return null;
}

function resolveAutoRole(role, hostRole) {
  const roleLc = String(role || '').trim().toLowerCase();
  if (roleLc && roleLc !== 'auto') return roleLc;
  if (hostRole === 'codex') return 'codex';
  if (hostRole === 'claude') return 'claude';
  return 'claude';
}

function parseCouncilConfig(configPath) {
  const fallback = {
    council: {
      chairman: { role: 'auto' },
      members: [
        { name: 'claude', command: 'claude -p', emoji: '🧠', color: 'CYAN' },
        { name: 'codex', command: 'codex exec', emoji: '🤖', color: 'BLUE' },
        { name: 'gemini', command: 'gemini', emoji: '💎', color: 'GREEN' },
      ],
      settings: { exclude_chairman_from_members: true, timeout: 120, parallel: true },
    },
  };

  if (!fs.existsSync(configPath)) return fallback;

  const content = fs.readFileSync(configPath, 'utf8');
  const lines = content.split(/\r?\n/);

  const result = { council: { chairman: {}, members: [], settings: {} } };
  let inCouncil = false;
  let councilIndent = 0;
  let inMembers = false;
  let membersIndent = 0;
  let inChairman = false;
  let chairmanIndent = 0;
  let inSettings = false;
  let settingsIndent = 0;

  let currentMember = null;

  function finalizeMember() {
    if (!currentMember) return;
    if (currentMember.name && currentMember.command) {
      result.council.members.push(currentMember);
    }
    currentMember = null;
  }

  function lineIndent(line) {
    const match = line.match(/^(\s*)/);
    return match ? match[1].length : 0;
  }

  function stripInlineComment(value) {
    const v = String(value || '').trim();
    if (!v) return v;
    const hashIndex = v.indexOf('#');
    if (hashIndex === -1) return v;
    return v.slice(0, hashIndex).trim();
  }

  function stripQuotes(value) {
    const v = stripInlineComment(value).trim();
    if (!v) return v;
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      return v.slice(1, -1);
    }
    return v;
  }

  for (const rawLine of lines) {
    const line = rawLine.replace(/\t/g, '    ');
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const indent = lineIndent(line);

    if (!inCouncil) {
      if (trimmed === 'council:' || trimmed.startsWith('council:')) {
        inCouncil = true;
        councilIndent = indent;
      }
      continue;
    }

    if (indent <= councilIndent && !trimmed.startsWith('-')) {
      inCouncil = false;
      inMembers = false;
      inChairman = false;
      inSettings = false;
      continue;
    }

    if (inMembers && indent <= membersIndent && !trimmed.startsWith('-')) {
      finalizeMember();
      inMembers = false;
    }
    if (inChairman && indent <= chairmanIndent) inChairman = false;
    if (inSettings && indent <= settingsIndent) inSettings = false;

    if (!inMembers && trimmed === 'members:') {
      inMembers = true;
      membersIndent = indent;
      continue;
    }
    if (!inChairman && trimmed === 'chairman:') {
      inChairman = true;
      chairmanIndent = indent;
      continue;
    }
    if (!inSettings && trimmed === 'settings:') {
      inSettings = true;
      settingsIndent = indent;
      continue;
    }

    if (inMembers) {
      const nameMatch = trimmed.match(/^- name:\s*(.+)$/);
      if (nameMatch) {
        finalizeMember();
        currentMember = { name: stripQuotes(nameMatch[1]) };
        continue;
      }

      const keyMatch = trimmed.match(/^([a-zA-Z0-9_]+):\s*(.*)$/);
      if (keyMatch && currentMember) {
        const key = keyMatch[1];
        const value = stripQuotes(keyMatch[2]);
        if (key === 'command') currentMember.command = value;
        else if (key === 'emoji') currentMember.emoji = value;
        else if (key === 'color') currentMember.color = value;
      }
      continue;
    }

    if (inChairman) {
      const roleMatch = trimmed.match(/^(role|name):\s*(.+)$/);
      if (roleMatch) {
        result.council.chairman.role = stripQuotes(roleMatch[2]);
      }
      continue;
    }

    if (inSettings) {
      const keyMatch = trimmed.match(/^([a-zA-Z0-9_]+):\s*(.+)$/);
      if (keyMatch) {
        const key = keyMatch[1];
        const value = stripQuotes(keyMatch[2]);
        result.council.settings[key] = value;
      }
      continue;
    }
  }

  finalizeMember();
  if (result.council.members.length === 0) return fallback;
  return result;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function safeFileName(name) {
  const cleaned = String(name || '').trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '-');
  return cleaned || 'member';
}

function atomicWriteJson(filePath, payload) {
  const tmpPath = `${filePath}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(payload, null, 2), 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function readJsonIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const args = argv.slice(2);
  const out = { _: [] };
  const booleanFlags = new Set([
    'json',
    'text',
    'help',
    'h',
    'include-chairman',
    'exclude-chairman',
  ]);
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--') {
      out._.push(...args.slice(i + 1));
      break;
    }
    if (!a.startsWith('--')) {
      out._.push(a);
      continue;
    }

    const [key, rawValue] = a.split('=', 2);
    if (rawValue != null) {
      out[key.slice(2)] = rawValue;
      continue;
    }

    const normalizedKey = key.slice(2);
    if (booleanFlags.has(normalizedKey)) {
      out[normalizedKey] = true;
      continue;
    }

    const next = args[i + 1];
    if (next == null || next.startsWith('--')) {
      out[normalizedKey] = true;
      continue;
    }
    out[normalizedKey] = next;
    i++;
  }
  return out;
}

function printHelp() {
  process.stdout.write(`Agent Council (job mode)

Usage:
  council-job.sh start [--config path] [--chairman auto|claude|codex|...] [--jobs-dir path] [--json] "question"
  council-job.sh status [--json|--text] <jobDir>
  council-job.sh results [--json] <jobDir>
  council-job.sh stop <jobDir>
  council-job.sh clean <jobDir>

Notes:
  - start returns immediately and runs members in parallel via detached Node workers
  - poll status with repeated short calls to update TODO/plan UIs in host agents
`);
}

function cmdStart(options, prompt) {
  const configPath = options.config || process.env.COUNCIL_CONFIG || resolveDefaultConfigFile();
  const jobsDir =
    options['jobs-dir'] || process.env.COUNCIL_JOBS_DIR || path.join(SKILL_DIR, '.jobs');

  ensureDir(jobsDir);

  const hostRole = detectHostRole();
  const config = parseCouncilConfig(configPath);
  const chairmanRoleRaw = options.chairman || process.env.COUNCIL_CHAIRMAN || config.council.chairman.role || 'auto';
  const chairmanRole = resolveAutoRole(chairmanRoleRaw, hostRole);

  const includeChairman = Boolean(options['include-chairman']);
  const excludeChairmanOverride =
    options['exclude-chairman'] != null ? true : options['include-chairman'] != null ? false : null;

  const excludeSetting = normalizeBool(config.council.settings.exclude_chairman_from_members);
  const excludeChairmanFromMembers =
    excludeChairmanOverride != null ? excludeChairmanOverride : excludeSetting != null ? excludeSetting : true;

  const timeoutSetting = Number(config.council.settings.timeout || 0);
  const timeoutOverride = options.timeout != null ? Number(options.timeout) : null;
  const timeoutSec = Number.isFinite(timeoutOverride) && timeoutOverride > 0 ? timeoutOverride : timeoutSetting > 0 ? timeoutSetting : 0;

  const requestedMembers = config.council.members || [];
  const members = requestedMembers.filter((m) => {
    if (!m || !m.name || !m.command) return false;
    const nameLc = String(m.name).toLowerCase();
    if (excludeChairmanFromMembers && !includeChairman && nameLc === chairmanRole) return false;
    return true;
  });

  const jobId = `${new Date().toISOString().replace(/[:.]/g, '').replace('T', '-').slice(0, 15)}-${crypto
    .randomBytes(3)
    .toString('hex')}`;
  const jobDir = path.join(jobsDir, `council-${jobId}`);
  const membersDir = path.join(jobDir, 'members');
  ensureDir(membersDir);

  fs.writeFileSync(path.join(jobDir, 'prompt.txt'), String(prompt), 'utf8');

  const jobMeta = {
    id: `council-${jobId}`,
    createdAt: new Date().toISOString(),
    configPath,
    hostRole,
    chairmanRole,
    settings: {
      excludeChairmanFromMembers,
      timeoutSec: timeoutSec || null,
    },
    members: members.map((m) => ({
      name: String(m.name),
      command: String(m.command),
      emoji: m.emoji ? String(m.emoji) : null,
      color: m.color ? String(m.color) : null,
    })),
  };
  atomicWriteJson(path.join(jobDir, 'job.json'), jobMeta);

  for (const member of members) {
    const name = String(member.name);
    const safeName = safeFileName(name);
    const memberDir = path.join(membersDir, safeName);
    ensureDir(memberDir);

    atomicWriteJson(path.join(memberDir, 'status.json'), {
      member: name,
      state: 'queued',
      queuedAt: new Date().toISOString(),
      command: String(member.command),
    });

    const workerArgs = [
      WORKER_PATH,
      '--job-dir',
      jobDir,
      '--member',
      name,
      '--safe-member',
      safeName,
      '--command',
      String(member.command),
    ];
    if (timeoutSec && Number.isFinite(timeoutSec) && timeoutSec > 0) {
      workerArgs.push('--timeout', String(timeoutSec));
    }

    const child = spawn(process.execPath, workerArgs, {
      detached: true,
      stdio: 'ignore',
      env: process.env,
    });
    child.unref();
  }

  if (options.json) {
    process.stdout.write(`${JSON.stringify({ jobDir, ...jobMeta }, null, 2)}\n`);
  } else {
    process.stdout.write(`${jobDir}\n`);
  }
}

function cmdStatus(options, jobDir) {
  const resolvedJobDir = path.resolve(jobDir);
  const jobMeta = readJsonIfExists(path.join(resolvedJobDir, 'job.json'));
  const membersRoot = path.join(resolvedJobDir, 'members');

  const members = [];
  if (fs.existsSync(membersRoot)) {
    for (const entry of fs.readdirSync(membersRoot)) {
      const statusPath = path.join(membersRoot, entry, 'status.json');
      const status = readJsonIfExists(statusPath);
      if (status) members.push({ safeName: entry, ...status });
    }
  }

  const totals = { queued: 0, running: 0, done: 0, error: 0, missing_cli: 0, timed_out: 0, canceled: 0 };
  for (const m of members) {
    const state = String(m.state || 'unknown');
    if (Object.prototype.hasOwnProperty.call(totals, state)) totals[state]++;
  }

  const allDone = members.length > 0 && totals.running === 0 && totals.queued === 0;
  const overallState = allDone ? 'done' : totals.running > 0 ? 'running' : 'queued';

  const payload = {
    jobDir: resolvedJobDir,
    id: jobMeta ? jobMeta.id : null,
    chairmanRole: jobMeta ? jobMeta.chairmanRole : null,
    overallState,
    counts: { total: members.length, ...totals },
    members: members
      .map((m) => ({
        member: m.member,
        state: m.state,
        startedAt: m.startedAt || null,
        finishedAt: m.finishedAt || null,
        exitCode: m.exitCode != null ? m.exitCode : null,
        message: m.message || null,
      }))
      .sort((a, b) => String(a.member).localeCompare(String(b.member))),
  };

  const wantText = Boolean(options.text) && !options.json;
  if (wantText) {
    const done = payload.counts.done + payload.counts.missing_cli + payload.counts.error + payload.counts.timed_out + payload.counts.canceled;
    process.stdout.write(`members ${done}/${payload.counts.total} done; running=${payload.counts.running} queued=${payload.counts.queued}\n`);
    for (const m of payload.members) {
      process.stdout.write(`- ${m.member}: ${m.state}${m.exitCode != null ? ` (exit ${m.exitCode})` : ''}\n`);
    }
    return;
  }

  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
}

function cmdResults(options, jobDir) {
  const resolvedJobDir = path.resolve(jobDir);
  const jobMeta = readJsonIfExists(path.join(resolvedJobDir, 'job.json'));
  const membersRoot = path.join(resolvedJobDir, 'members');

  const members = [];
  if (fs.existsSync(membersRoot)) {
    for (const entry of fs.readdirSync(membersRoot)) {
      const statusPath = path.join(membersRoot, entry, 'status.json');
      const outputPath = path.join(membersRoot, entry, 'output.txt');
      const errorPath = path.join(membersRoot, entry, 'error.txt');
      const status = readJsonIfExists(statusPath);
      if (!status) continue;
      const output = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, 'utf8') : '';
      const stderr = fs.existsSync(errorPath) ? fs.readFileSync(errorPath, 'utf8') : '';
      members.push({ safeName: entry, ...status, output, stderr });
    }
  }

  if (options.json) {
    process.stdout.write(
      `${JSON.stringify(
        {
          jobDir: resolvedJobDir,
          id: jobMeta ? jobMeta.id : null,
          prompt: fs.existsSync(path.join(resolvedJobDir, 'prompt.txt'))
            ? fs.readFileSync(path.join(resolvedJobDir, 'prompt.txt'), 'utf8')
            : null,
          members: members
            .map((m) => ({
              member: m.member,
              state: m.state,
              exitCode: m.exitCode != null ? m.exitCode : null,
              message: m.message || null,
              output: m.output,
              stderr: m.stderr,
            }))
            .sort((a, b) => String(a.member).localeCompare(String(b.member))),
        },
        null,
        2
      )}\n`
    );
    return;
  }

  for (const m of members.sort((a, b) => String(a.member).localeCompare(String(b.member)))) {
    process.stdout.write(`\n=== ${m.member} (${m.state}) ===\n`);
    if (m.message) process.stdout.write(`${m.message}\n`);
    process.stdout.write(m.output || '');
    if (!m.output && m.stderr) {
      process.stdout.write('\n');
      process.stdout.write(m.stderr);
    }
    process.stdout.write('\n');
  }
}

function cmdStop(_options, jobDir) {
  const resolvedJobDir = path.resolve(jobDir);
  const membersRoot = path.join(resolvedJobDir, 'members');
  if (!fs.existsSync(membersRoot)) exitWithError(`No members folder found: ${membersRoot}`);

  let stoppedAny = false;
  for (const entry of fs.readdirSync(membersRoot)) {
    const statusPath = path.join(membersRoot, entry, 'status.json');
    const status = readJsonIfExists(statusPath);
    if (!status) continue;
    if (status.state !== 'running') continue;
    if (!status.pid) continue;

    try {
      process.kill(Number(status.pid), 'SIGTERM');
      stoppedAny = true;
    } catch {
      // ignore
    }
  }

  process.stdout.write(stoppedAny ? 'stop: sent SIGTERM to running members\n' : 'stop: no running members\n');
}

function cmdClean(_options, jobDir) {
  const resolvedJobDir = path.resolve(jobDir);
  fs.rmSync(resolvedJobDir, { recursive: true, force: true });
  process.stdout.write(`cleaned: ${resolvedJobDir}\n`);
}

function main() {
  const options = parseArgs(process.argv);
  const [command, ...rest] = options._;

  if (!command || options.help || options.h) {
    printHelp();
    return;
  }

  if (command === 'start') {
    const prompt = rest.join(' ').trim();
    if (!prompt) exitWithError('start: missing prompt');
    cmdStart(options, prompt);
    return;
  }
  if (command === 'status') {
    const jobDir = rest[0];
    if (!jobDir) exitWithError('status: missing jobDir');
    cmdStatus(options, jobDir);
    return;
  }
  if (command === 'results') {
    const jobDir = rest[0];
    if (!jobDir) exitWithError('results: missing jobDir');
    cmdResults(options, jobDir);
    return;
  }
  if (command === 'stop') {
    const jobDir = rest[0];
    if (!jobDir) exitWithError('stop: missing jobDir');
    cmdStop(options, jobDir);
    return;
  }
  if (command === 'clean') {
    const jobDir = rest[0];
    if (!jobDir) exitWithError('clean: missing jobDir');
    cmdClean(options, jobDir);
    return;
  }

  exitWithError(`Unknown command: ${command}`);
}

if (require.main === module) {
  main();
}
