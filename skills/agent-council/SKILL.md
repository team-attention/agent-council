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
JOB_DIR=$(./skills/agent-council/scripts/council.sh start "your question here")
./skills/agent-council/scripts/council.sh status --text "$JOB_DIR"
./skills/agent-council/scripts/council.sh status --checklist "$JOB_DIR"
./skills/agent-council/scripts/council.sh wait "$JOB_DIR" # returns JSON + persists a cursor for blocking waits
./skills/agent-council/scripts/council.sh results "$JOB_DIR"
./skills/agent-council/scripts/council.sh clean "$JOB_DIR"
```

One-shot (runs job → waits → prints results → cleans):

```bash
./skills/agent-council/scripts/council.sh "your question here"
```

Note:
- In host-agent tool UIs (Codex CLI / Claude Code), one-shot does **not** block (so the host can update native plan/todo UIs). It returns a single `wait` JSON payload, and the host should continue with `wait` → native UI update → `results` → `clean`.

### Execution via Host Agent (progress, no tool-cell spam)

When using this skill inside a host agent (Codex CLI / Claude Code), some UIs do not stream long-running tool output. Prefer **job mode + `wait`** so the host agent can update a native checklist (e.g. `update_plan`) with only a few tool calls.

```bash
JOB_DIR=$(./skills/agent-council/scripts/council.sh start "your question here")
./skills/agent-council/scripts/council.sh wait "$JOB_DIR" # returns immediately (seeds cursor + JSON payload)
# Host agent MUST now call its native checklist tool:
# - Codex CLI: update_plan(.ui.codex.update_plan.plan)
# - Claude Code: TodoWrite(.ui.claude.todo_write.todos)
./skills/agent-council/scripts/council.sh wait "$JOB_DIR" # blocks until meaningful progress
# Host agent updates the native checklist again after each wait return
./skills/agent-council/scripts/council.sh results "$JOB_DIR"
./skills/agent-council/scripts/council.sh clean "$JOB_DIR"
```

Notes:
- `wait` prints JSON, remembers its cursor in `<jobDir>/.wait_cursor`, and returns only when progress meaningfully changes.
- Default `wait` auto-batches to a small number of updates (typically ~5–10 total; `--bucket 1` for every completion).
- One-shot prints progress in a normal terminal, but may not render live inside some host agent tool UIs.

**Recommended host-agent checklist strategy (`update_plan`):**
- `wait` JSON includes a pre-built council checklist you can feed into native UIs:
  - Codex CLI: `update_plan` input at `.ui.codex.update_plan.plan`
  - Claude Code: `TodoWrite` input at `.ui.claude.todo_write.todos`
- IMPORTANT: The native checklist UI can only be updated by the host agent. Shell scripts cannot force it to appear.
- IMPORTANT (Codex): Don’t run a blocking `wait` call before calling `update_plan` at least once, or the Plan UI won’t show until the wait returns.
- Preserve any existing items as-is, and append the `[Council]` section (so the user’s TODO list doesn’t “disappear”).
- The default council checklist is intentionally small (`N + 2` items):
  - `[Council] Prompt dispatch`
  - One line per member: `[Council] Ask <member>` (checkbox marks completion)
  - `[Council] Synthesize`
  - (With the default config, `N` is usually 2 because the chairman is excluded, so you’ll typically see 4 items total.)
- Default checklist uses only `pending` → `completed` (no `in_progress`). If you extend it, keep at most one `in_progress` at a time (Codex plan UI expects this).
- Don’t run a long `while true` loop in a single shell tool call; update the UI only after each `wait` return (auto-batched), then restore the original list (or remove the `[Council]` section) when finished.

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

Council members are configured in `council.config.yaml`. The installer enables only detected CLIs and (by default) excludes the host chairman from members.

| Agent | CLI Command | Characteristics |
|-------|-------------|-----------------|
| Claude Code | `claude -p` | Thoughtful, structured reasoning |
| OpenAI Codex | `codex exec` | Code-focused, pragmatic approach |
| Google Gemini | `gemini` | Broad knowledge, diverse perspectives |
| Chairman (auto) | - | Synthesis and final judgment (by your host agent) |

## Requirements

- Each configured CLI must be installed and authenticated
- Template includes: Claude CLI, OpenAI Codex CLI, Google Gemini CLI
- Requires Node.js (plugins can’t bundle or auto-install it)

### Verify Installation

```bash
claude --version
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
    - name: claude
      command: "claude -p"
      emoji: "🧠"
      color: "CYAN"
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
