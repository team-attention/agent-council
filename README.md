# Agent Council

**[한국어 버전 (Korean)](./README.ko.md)**

> A skill that gathers opinions from multiple AI CLIs (Codex, Gemini, ...) and lets a configurable Chairman synthesize a conclusion.
> Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)

## Key Difference from LLM Council

**No additional API costs!**

Unlike Karpathy's LLM Council which directly calls each LLM's API (incurring costs), Agent Council uses your installed AI CLIs (Claude Code, Codex CLI, Gemini CLI, ...). This is especially useful if you mainly use one host CLI and occasionally consult others via subscriptions.

Skills are much simpler and more reproducible than MCP. We recommend installing via npx and customizing it yourself!

## Demo

https://github.com/user-attachments/assets/c550c473-00d2-4def-b7ba-654cc7643e9b

## How it Works

Agent Council implements a 3-stage process for gathering AI consensus:

**Stage 1: Initial Opinions**
All configured AI agents receive your question simultaneously and respond independently.

**Stage 2: Response Collection**
Responses from each agent are collected and displayed to you in a formatted view.

**Stage 3: Chairman Synthesis**
Your host agent (Claude Code / Codex CLI / etc.) acts as the Chairman by default (`role: auto`), synthesizing all opinions into a final recommendation. Optionally, you can configure a Chairman CLI command to run synthesis inside `council.sh`.

## Setup

### Option A: Install via npx (Recommended)

```bash
npx github:team-attention/agent-council
```

This copies the skill files to your current project directory.

By default, the installer auto-detects whether to install for Claude Code (`.claude/`) and/or Codex CLI (`.codex/`) based on what’s available on your machine and in the repo.

Installed paths:
- `.claude/skills/agent-council/` (Claude Code)
- `.codex/skills/agent-council/` (Codex CLI)

Optional (Codex repo skill):
```bash
npx github:team-attention/agent-council --target codex
```

Other targets:
```bash
npx github:team-attention/agent-council --target claude
npx github:team-attention/agent-council --target both
```

The generated `council.config.yaml` enables only detected member CLIs (e.g. `claude`, `codex`, `gemini`) and avoids adding the host target as a member.

### Option B: Install via Claude Code Plugin (Claude Code only)

```bash
# Add the marketplace
/plugin marketplace add team-attention/agent-council

# Install the plugin
/plugin install agent-council@team-attention-plugins
```

### 2. Install Agent CLIs

Install the CLIs you want to use as council members (template includes `claude`, `codex`, `gemini`):

```bash
# Anthropic Claude Code
# https://claude.ai/code

# OpenAI Codex CLI
# https://github.com/openai/codex

# Google Gemini CLI
# https://github.com/google-gemini/gemini-cli
```

Verify installation:
```bash
claude --version
codex --version
gemini --version
```

### 3. Configure Council Members (Optional)

Edit the generated config in your installed skill directory:
- `.claude/skills/agent-council/council.config.yaml`
- `.codex/skills/agent-council/council.config.yaml`

```yaml
council:
  chairman:
    role: "auto" # auto|claude|codex|gemini|...
    # command: "codex exec" # optional: run Stage 3 inside council.sh

  members:
    - name: codex
      command: "codex exec"
      emoji: "🤖"
      color: "BLUE"

    - name: gemini
      command: "gemini"
      emoji: "💎"
      color: "GREEN"

    # Add more agents as needed
    # - name: grok
    #   command: "grok"
    #   emoji: "🚀"
    #   color: "MAGENTA"
```

## Usage

### Via your host agent (Claude Code / Codex CLI)

Ask your host agent to summon the council:

```
"Let's hear opinions from other AIs"
"Summon the council"
"Review this from multiple perspectives"
"Ask codex and gemini for their opinions"
```

### Direct Script Execution

```bash
.claude/skills/agent-council/scripts/council.sh "Your question here"
# or
.codex/skills/agent-council/scripts/council.sh "Your question here"
```

### Live Progress (Job Mode)

If your host UI doesn’t feel “live” during a long `council.sh` run, use job mode: it starts member runs in parallel in the background and lets you poll progress with short commands (useful for TODO/plan updates).

```bash
JOB_DIR=$(.codex/skills/agent-council/scripts/council-job.sh start "Your question here")
.codex/skills/agent-council/scripts/council-job.sh status --text "$JOB_DIR"
.codex/skills/agent-council/scripts/council-job.sh results "$JOB_DIR"
.codex/skills/agent-council/scripts/council-job.sh clean "$JOB_DIR"
```

## Example

```
User: "React vs Vue for a new dashboard project - summon the council"

Host agent (Claude Code / Codex CLI):
1. Executes council.sh to collect opinions from configured members (e.g., Codex, Gemini)
2. Displays each agent's perspective
3. Synthesizes as Chairman:
   "Based on the council's input, considering your dashboard's
   data visualization needs and team's familiarity, I recommend..."
```

## Project Structure

```
agent-council/
├── .claude-plugin/
│   └── marketplace.json     # Marketplace config (Claude Code only)
├── bin/
│   └── install.js           # npx installer
├── skills/
│   └── agent-council/
│       ├── SKILL.md         # Skill documentation
│       └── scripts/
│           ├── council.sh       # Execution script
│           ├── council-job.sh   # Background job runner (pollable)
│           ├── council-job.js   # Job runner implementation
│           └── council-job-worker.js # Per-member worker
├── council.config.yaml      # Council member configuration
├── README.md                # This file
├── README.ko.md             # Korean documentation
└── LICENSE
```

## Notes

- Response time depends on the slowest agent (parallel execution)
- Do not share sensitive information with the council
- Agents run in parallel by default for faster responses
- Subscription plans for each CLI tool are required (no additional API costs)

## Contributing

Contributions are welcome! Feel free to:
- Add support for new AI agents
- Improve the synthesis process
- Enhance the configuration options

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Credits

- Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)
- Built for [Claude Code](https://claude.ai/code) and [Codex CLI](https://github.com/openai/codex)
