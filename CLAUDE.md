# Project Instructions (Claude Code)

## Todo UI (IMPORTANT)

- When you decide to use any Skill, **always** call `TodoWrite` immediately (before any potentially long-running shell/tool calls) so Claude’s Todo UI appears. Include **exactly one** `in_progress` item in that first todo list.
- Keep the todo list updated during execution (at most one `in_progress` item at a time).
- For `agent-council`: after the first `council.sh wait` (the non-blocking one), feed `.ui.claude.todo_write.todos` into `TodoWrite` right away, then repeat `wait → TodoWrite` until done.

