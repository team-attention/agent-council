#!/bin/bash
#
# Agent Council (job mode default)
#
# Subcommands:
#   council.sh start [options] "question"     # returns JOB_DIR immediately
#   council.sh status [--json|--text|--checklist] JOB_DIR # poll progress
#   council.sh wait [--cursor CURSOR] [--bucket auto|N] [--interval-ms N] [--timeout-ms N] JOB_DIR
#   council.sh results [--json] JOB_DIR       # print collected outputs
#   council.sh stop JOB_DIR                   # best-effort stop running members
#   council.sh clean JOB_DIR                  # remove job directory
#
# One-shot:
#   council.sh "question"
#   (in a real terminal: starts a job, waits for completion, prints results, cleans up)
#   (in host-agent tool UIs: returns a single `wait` JSON payload immediately; host drives progress + results)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_SCRIPT="$SCRIPT_DIR/council-job.sh"

usage() {
  cat <<EOF
Agent Council

Default mode is job-based parallel execution (pollable).

Usage:
  $(basename "$0") start [options] "question"
  $(basename "$0") status [--json|--text|--checklist] <jobDir>
  $(basename "$0") wait [--cursor CURSOR] [--bucket auto|N] [--interval-ms N] [--timeout-ms N] <jobDir>
  $(basename "$0") results [--json] <jobDir>
  $(basename "$0") stop <jobDir>
  $(basename "$0") clean <jobDir>

One-shot:
  $(basename "$0") "question"
EOF
}

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js is required to run Agent Council." >&2
  echo "Claude Code plugins cannot bundle or auto-install Node." >&2
  echo "" >&2
  echo "macOS (Homebrew): brew install node" >&2
  echo "Or download from: https://nodejs.org/" >&2
  exit 127
fi

case "$1" in
  start|status|wait|results|stop|clean)
    exec "$JOB_SCRIPT" "$@"
    ;;
esac

in_host_agent_context() {
  if [ -n "${CODEX_CACHE_FILE:-}" ]; then
    return 0
  fi

  case "$SCRIPT_DIR" in
    */.codex/skills/*|*/.claude/skills/*)
      # Tool-call environments typically do not provide a real TTY on stdout/stderr.
      if [ ! -t 1 ] && [ ! -t 2 ]; then
        return 0
      fi
      ;;
  esac

  return 1
}

JOB_DIR="$("$JOB_SCRIPT" start "$@")"

# Host agents (Codex CLI / Claude Code) cannot update native TODO/plan UIs while a long-running
# command is executing. If we're in a host agent context, return immediately with a single `wait`
# JSON payload (includes `.ui.codex.update_plan.plan` / `.ui.claude.todo_write.todos`) and let the
# host agent drive progress updates with repeated short `wait` calls + native UI updates.
if in_host_agent_context; then
  exec "$JOB_SCRIPT" wait "$JOB_DIR"
fi

SHOW_PROGRESS="${COUNCIL_PROGRESS:-1}"
TUI_MODE="${COUNCIL_TUI:-auto}"
TUI_MODE_NORM="$(printf '%s' "$TUI_MODE" | tr '[:upper:]' '[:lower:]')"
if [ -z "$TUI_MODE_NORM" ]; then
  TUI_MODE_NORM="auto"
fi
USE_CHECKLIST="0"
CHECKLIST_ACTIVE="0"
LAST_PROGRESS_LINE=""
LAST_CHECKLIST_SCREEN=""
LAST_CHECKLIST_KEY=""
CHECKLIST_LINES="0"

checklist_enter() {
  # Hide cursor for nicer redraws when ANSI is supported
  if can_use_ansi; then
    CHECKLIST_ACTIVE="1"
    printf '\033[?25l\033[0m' >&2
  fi
}

checklist_exit() {
  if [ "$CHECKLIST_ACTIVE" = "1" ]; then
    CHECKLIST_ACTIVE="0"
    printf '\033[?25h\033[0m\n' >&2
  fi
}

checklist_render() {
  local screen="$1"
  case "$screen" in
    *$'\n') ;;
    *) screen="${screen}"$'\n' ;;
  esac
  if can_use_ansi; then
    if [ "${CHECKLIST_LINES:-0}" -gt 0 ]; then
      printf '\033[%dA' "$CHECKLIST_LINES" >&2
    fi
    printf '\033[J' >&2
    printf '%s' "$screen" >&2
    CHECKLIST_LINES="$(printf '%s' "$screen" | awk 'END{print NR}')"
  else
    printf '%s' "$screen" >&2
  fi
}

ui_cleanup() {
  checklist_exit
}

can_use_ansi() {
  # Requires a real terminal on stderr; some host UIs may not render cursor movement/clears.
  [ -t 2 ] && [ "${TERM:-dumb}" != "dumb" ]
}

if [ "$SHOW_PROGRESS" != "0" ]; then
  case "$TUI_MODE_NORM" in
    0|false|no|n|off)
      USE_CHECKLIST="0"
      ;;
    checklist|checks|checkboxes)
      USE_CHECKLIST="1"
      ;;
    1|true|yes|y|on|auto|*)
      USE_CHECKLIST="1"
      ;;
  esac
fi

if [ "$USE_CHECKLIST" = "1" ]; then
  trap ui_cleanup EXIT INT TERM
  checklist_enter
fi

while true; do
  STATUS_JSON="$("$JOB_SCRIPT" status --json "$JOB_DIR")"
  if [ "$USE_CHECKLIST" = "1" ]; then
    STATUS_INFO="$(printf '%s' "$STATUS_JSON" | node -e '
const fs=require("fs");
const d=JSON.parse(fs.readFileSync(0,"utf8"));
const counts=d.counts||{};
const done=(counts.done||0)+(counts.missing_cli||0)+(counts.error||0)+(counts.timed_out||0)+(counts.canceled||0);
const total=counts.total||0;
const members=(d.members||[]).slice().sort((a,b)=>String(a.member).localeCompare(String(b.member)));
const key=`${done}/${total}`;
const mark=(state)=>state==="done" ? "[x]" : (state==="running"||state==="queued") ? "[ ]" : "[!]";
const lines=[];
lines.push("Agent Council");
if (d.id) lines.push(`Job: ${d.id}`);
lines.push(`Progress: ${done}/${total} done  (running ${counts.running||0}, queued ${counts.queued||0})`);
for (const m of members) {
  const state=String(m.state||"");
  const display=(state==="running"||state==="queued") ? "working" : state;
  lines.push(`${mark(state)} ${m.member} — ${display}${m.exitCode!=null ? ` (exit ${m.exitCode})` : ""}`);
}
process.stdout.write(String(d.overallState||"") + "\n" + key + "\n" + lines.join("\n") + "\n");
')"
    OVERALL="${STATUS_INFO%%$'\n'*}"
    REST="${STATUS_INFO#*$'\n'}"
    CHECKLIST_KEY="${REST%%$'\n'*}"
    CHECKLIST_SCREEN="${REST#*$'\n'}"
    if [ "$CHECKLIST_KEY" != "$LAST_CHECKLIST_KEY" ]; then
      checklist_render "$CHECKLIST_SCREEN"
      LAST_CHECKLIST_KEY="$CHECKLIST_KEY"
      LAST_CHECKLIST_SCREEN="$CHECKLIST_SCREEN"
    fi
  else
    STATUS_INFO="$(printf '%s' "$STATUS_JSON" | node -e '
const fs=require("fs");
const d=JSON.parse(fs.readFileSync(0,"utf8"));
const counts=d.counts||{};
const done=(counts.done||0)+(counts.missing_cli||0)+(counts.error||0)+(counts.timed_out||0)+(counts.canceled||0);
const total=counts.total||0;
const summary=`council: ${done}/${total} done; running=${counts.running||0} queued=${counts.queued||0}`;
process.stdout.write(String(d.overallState||"") + "\n" + summary);
')"
    OVERALL="${STATUS_INFO%%$'\n'*}"
    PROGRESS_LINE="${STATUS_INFO#*$'\n'}"

    if [ "$SHOW_PROGRESS" != "0" ] && [ "$PROGRESS_LINE" != "$LAST_PROGRESS_LINE" ]; then
      echo "$PROGRESS_LINE" >&2
      LAST_PROGRESS_LINE="$PROGRESS_LINE"
    fi
  fi
  if [ "$OVERALL" = "done" ]; then
    break
  fi
  sleep 0.5
done

if [ "$USE_CHECKLIST" = "1" ]; then
  checklist_exit
  trap - EXIT INT TERM
fi

"$JOB_SCRIPT" results "$JOB_DIR"
"$JOB_SCRIPT" clean "$JOB_DIR" >/dev/null
