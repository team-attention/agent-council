---
name: agent-council
description: Collect and synthesize opinions from multiple AI Agents. Use when users say "summon the council", "ask other AIs", or want multiple AI perspectives on a question.
---

# Agent Council

> Collect and synthesize opinions from multiple AI Agents
> Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council)

## Overview

Agent Council gathers opinions from multiple AI Agents (Codex, Gemini, etc.) when facing difficult questions or decisions. A configurable Chairman then synthesizes the final response (default: `role: auto`, meaning the host agent you’re using).

## Trigger Conditions

This skill activates when:
- "Let's hear opinions from other AIs"
- "Summon the council"
- "Review this from multiple perspectives"
- "Ask codex and gemini for their opinions"
- "council"
- "$agent-council"

## 3-Stage Process (LLM Council Method)

### Stage 1: Initial Opinions
Send the same question to each council member to collect initial opinions

### Stage 2: Response Collection
Collect and display each Agent's response to the user

### Stage 3: Chairman Synthesis
The Chairman synthesizes all responses and presents the final opinion (usually handled by the host agent; optionally can be executed inside `council.sh` via `chairman.command`)

## Usage

### Direct Script Execution

```bash
./skills/agent-council/scripts/council.sh "your question here"
```

### Execution via Host Agent

1. Request council summon from your host agent (Claude Code / Codex CLI)
2. The host agent executes the script to collect each Agent's opinion
3. The host agent synthesizes as Chairman and presents the final recommendation

## Examples

### Technical Decision Making

```
User: "React vs Vue - which fits this project better? Summon the council"

Host agent:
1. Execute council.sh to collect opinions from configured members (e.g., Codex, Gemini)
2. Organize each Agent's perspective
3. Recommend based on project context
```

### Architecture Review

```
User: "Let's hear other AIs' opinions on this design"

Host agent:
1. Summarize current design and query the council
2. Collect feedback from each Agent
3. Analyze commonalities/differences and provide synthesis
```

## Council Members

Council members are configured in `council.config.yaml`. Default members:

| Agent | CLI Command | Characteristics |
|-------|-------------|-----------------|
| OpenAI Codex | `codex exec` | Code-focused, pragmatic approach |
| Google Gemini | `gemini` | Broad knowledge, diverse perspectives |
| Chairman (auto) | - | Synthesis and final judgment (by your host agent) |

## Requirements

- Each configured CLI must be installed and authenticated
- Default: OpenAI Codex CLI, Google Gemini CLI

### Verify Installation

```bash
codex --version
gemini --version
```

## Configuration

Edit `council.config.yaml` to customize council members:

```yaml
council:
  chairman:
    role: "auto"
  members:
    - name: codex
      command: "codex exec"
      emoji: "🤖"
      color: "BLUE"
    - name: gemini
      command: "gemini"
      emoji: "💎"
      color: "GREEN"
```

## File Structure

```
skills/agent-council/
├── SKILL.md              # This document
└── scripts/
    └── council.sh        # Council execution script
```

## Notes

- Costs and auth depend on each Agent CLI
- Response time depends on the slowest Agent
- Do not share sensitive information with the council
