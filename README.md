# Agent Council

**[한국어 버전 (Korean)](./README.ko.md)**

> A Claude Code plugin that collects and synthesizes opinions from multiple AI Agents.
> Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)

## Demo

https://github.com/user-attachments/assets/c550c473-00d2-4def-b7ba-654cc7643e9b

## How it Works

Agent Council implements a 3-stage process for gathering AI consensus:

**Stage 1: Initial Opinions**
All configured AI agents receive your question simultaneously and respond independently.

**Stage 2: Response Collection**
Responses from each agent are collected and displayed to you in a formatted view.

**Stage 3: Chairman Synthesis**
Claude acts as the Chairman, synthesizing all opinions into a final recommendation based on commonalities, differences, and context.

## Setup

### Option A: Install via npx (Recommended)

```bash
npx github:team-attention/agent-council
```

This copies the skill files to your current project directory.

### Option B: Install via Claude Code Plugin

```bash
# Add the marketplace
/plugin marketplace add team-attention/agent-council

# Install the plugin
/plugin install agent-council@team-attention-plugins
```

### 2. Install Agent CLIs

The default configuration requires:

```bash
# OpenAI Codex CLI
# https://github.com/openai/codex

# Google Gemini CLI
# https://github.com/google-gemini/gemini-cli
```

Verify installation:
```bash
codex --version
gemini --version
```

### 3. Configure Council Members (Optional)

Edit `council.config.yaml` to customize your council:

```yaml
council:
  members:
    - name: codex
      command: "codex exec"
      emoji: "🤖"
      color: "BLUE"
      description: "OpenAI Codex - Code-focused, pragmatic approach"

    - name: gemini
      command: "gemini"
      emoji: "💎"
      color: "GREEN"
      description: "Google Gemini - Broad knowledge, diverse perspectives"

    # Add more agents as needed
    # - name: grok
    #   command: "grok"
    #   emoji: "🚀"
    #   color: "MAGENTA"
```

## Usage

### Via Claude

Simply ask Claude to summon the council:

```
"Let's hear opinions from other AIs"
"Summon the council"
"Review this from multiple perspectives"
"Ask codex and gemini for their opinions"
```

### Direct Script Execution

```bash
./skills/agent-council/scripts/council.sh "Your question here"
```

## Example

```
User: "React vs Vue for a new dashboard project - summon the council"

Claude:
1. Executes council.sh to collect opinions from Codex and Gemini
2. Displays each agent's perspective
3. Synthesizes as Chairman:
   "Based on the council's input, considering your dashboard's
   data visualization needs and team's familiarity, I recommend..."
```

## Project Structure

```
agent-council/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Marketplace config
├── skills/
│   └── agent-council/
│       ├── SKILL.md         # Skill documentation
│       └── scripts/
│           └── council.sh   # Execution script
├── council.config.yaml      # Council member configuration
├── README.md                # This file
├── README.ko.md             # Korean documentation
└── LICENSE
```

## Notes

- API costs are incurred for each agent call
- Response time depends on the slowest agent (parallel execution)
- Do not share sensitive information with the council
- Agents run in parallel by default for faster responses

## Contributing

Contributions are welcome! Feel free to:
- Add support for new AI agents
- Improve the synthesis process
- Enhance the configuration options

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Credits

- Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)
- Built for [Claude Code](https://claude.ai/code)
