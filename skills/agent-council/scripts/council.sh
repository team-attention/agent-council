#!/bin/bash
#
# Agent Council (job mode default)
#
# Subcommands:
#   council.sh start [options] "question"     # returns JOB_DIR immediately
#   council.sh status [--json|--text] JOB_DIR # poll progress
#   council.sh results [--json] JOB_DIR       # print collected outputs
#   council.sh stop JOB_DIR                   # best-effort stop running members
#   council.sh clean JOB_DIR                  # remove job directory
#
# One-shot:
#   council.sh "question"
#   (starts a job, waits for completion, prints results, cleans up)
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
  $(basename "$0") status [--json|--text] <jobDir>
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
  start|status|results|stop|clean)
    exec "$JOB_SCRIPT" "$@"
    ;;
esac

JOB_DIR="$("$JOB_SCRIPT" start "$@")"

while true; do
  OVERALL="$("$JOB_SCRIPT" status --json "$JOB_DIR" | node -e 'const fs=require("fs");const d=JSON.parse(fs.readFileSync(0,"utf8"));process.stdout.write(String(d.overallState||""));')"
  if [ "$OVERALL" = "done" ]; then
    break
  fi
  sleep 0.5
done

"$JOB_SCRIPT" results "$JOB_DIR"
"$JOB_SCRIPT" clean "$JOB_DIR" >/dev/null
