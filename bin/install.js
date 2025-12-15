#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';
const RED = '\x1b[31m';
const NC = '\x1b[0m';

const packageRoot = path.resolve(__dirname, '..');
const targetDir = process.cwd();
const claudeDir = path.join(targetDir, '.claude');
const codexDir = path.join(targetDir, '.codex');

function parseArgs(argv) {
  const args = argv.slice(2);
  const flags = new Set(args);

  const targetIndex = args.indexOf('--target');
  let target = 'claude';
  if (targetIndex !== -1 && args[targetIndex + 1]) {
    target = args[targetIndex + 1];
  } else if (flags.has('--both')) {
    target = 'both';
  } else if (flags.has('--codex')) {
    target = 'codex';
  } else if (flags.has('--claude')) {
    target = 'claude';
  }

  if (!['claude', 'codex', 'both'].includes(target)) {
    throw new Error(`Invalid --target "${target}". Use claude|codex|both.`);
  }

  return { target };
}

console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
console.log(`${CYAN}  Agent Council - Installation${NC}`);
console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
console.log();

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);

  if (stat.isDirectory()) {
    if (!fs.existsSync(dest)) {
      fs.mkdirSync(dest, { recursive: true });
    }
    const files = fs.readdirSync(src);
    for (const file of files) {
      copyRecursive(path.join(src, file), path.join(dest, file));
    }
  } else {
    fs.copyFileSync(src, dest);
    // Preserve executable permission for .sh files
    if (src.endsWith('.sh')) {
      fs.chmodSync(dest, 0o755);
    }
  }
}

try {
  const { target } = parseArgs(process.argv);

  const installs = [];
  if (target === 'claude' || target === 'both') {
    installs.push({
      label: 'Claude Code',
      rootDir: claudeDir,
      skillsDest: path.join(claudeDir, 'skills', 'agent-council'),
      displayPath: '.claude/skills/agent-council',
    });
  }
  if (target === 'codex' || target === 'both') {
    installs.push({
      label: 'Codex CLI',
      rootDir: codexDir,
      skillsDest: path.join(codexDir, 'skills', 'agent-council'),
      displayPath: '.codex/skills/agent-council',
    });
  }

  // Copy skills folder to target(s)
  const skillsSrc = path.join(packageRoot, 'skills', 'agent-council');
  const configSrc = path.join(packageRoot, 'council.config.yaml');

  for (const install of installs) {
    if (!fs.existsSync(install.rootDir)) {
      fs.mkdirSync(install.rootDir, { recursive: true });
    }

    if (fs.existsSync(skillsSrc)) {
      console.log(`${YELLOW}Installing skills (${install.label})...${NC}`);
      copyRecursive(skillsSrc, install.skillsDest);
      console.log(`${GREEN}  ✓ ${install.displayPath}${NC}`);
    }

    // Copy config file to skill folder if not exists
    const configDest = path.join(install.skillsDest, 'council.config.yaml');
    if (fs.existsSync(configSrc) && !fs.existsSync(configDest)) {
      console.log(`${YELLOW}Installing config (${install.label})...${NC}`);
      fs.copyFileSync(configSrc, configDest);
      console.log(`${GREEN}  ✓ ${install.displayPath}/council.config.yaml${NC}`);
    } else if (fs.existsSync(configDest)) {
      console.log(`${YELLOW}  ⓘ council.config.yaml already exists (${install.label}), skipping${NC}`);
    }
  }

  console.log();
  console.log(`${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log(`${GREEN}  Installation complete!${NC}`);
  console.log(`${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log();
  console.log(`${CYAN}Usage in Claude:${NC}`);
  console.log(`  "Summon the council"`);
  console.log(`  "Let's hear opinions from other AIs"`);
  console.log();
  console.log(`${CYAN}Direct execution:${NC}`);
  console.log(`  .claude/skills/agent-council/scripts/council.sh "your question"`);
  console.log(`  .codex/skills/agent-council/scripts/council.sh "your question"`);
  console.log();
  console.log(`${YELLOW}Note: Make sure codex and gemini CLIs are installed.${NC}`);

} catch (error) {
  console.error(`${RED}Error during installation: ${error.message}${NC}`);
  process.exit(1);
}
