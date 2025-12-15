#!/bin/bash
#
# Agent Council - Collect opinions from multiple AI Agents
#
# Usage:
#   council.sh [options] "question or prompt"
#
# Options:
#   -c, --config <path>           Use a specific config file path
#       --chairman <role|auto>    Set chairman role (auto|claude|codex|gemini|...)
#       --chairman-command <cmd>  Run Stage 3 synthesis via this CLI command
#       --synthesize              Force Stage 3 synthesis (requires chairman command or inferrable)
#       --no-synthesize           Disable Stage 3 synthesis (default when no chairman command)
#       --include-chairman        Do not filter chairman out of members
#       --exclude-chairman        Filter chairman out of members (default)
#   -h, --help                    Show help
#
# LLM Council (Karpathy) concept:
# - Stage 1: Send same question to each Agent
# - Stage 2: Collect and output responses
# - Stage 3: Chairman synthesizes (optional; can be external or via CLI)
#

set -e

# Get script directory and find config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_CONFIG_FILE="$SKILL_DIR/council.config.yaml"
REPO_CONFIG_FILE="$(cd "$SKILL_DIR/../.." && pwd)/council.config.yaml"

resolve_default_config_file() {
    if [ -f "$SKILL_CONFIG_FILE" ]; then
        echo "$SKILL_CONFIG_FILE"
    elif [ -f "$REPO_CONFIG_FILE" ]; then
        echo "$REPO_CONFIG_FILE"
    else
        echo "$SKILL_CONFIG_FILE"
    fi
}

DEFAULT_CONFIG_FILE="$(resolve_default_config_file)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Agent Council - Collect opinions from multiple AI Agents

Usage:
  $(basename "$0") [options] "question or prompt"

Options:
  -c, --config <path>           Use a specific config file path
      --chairman <role|auto>    Set chairman role (auto|claude|codex|gemini|...)
      --chairman-command <cmd>  Run Stage 3 synthesis via this CLI command
      --synthesize              Force Stage 3 synthesis (requires chairman command or inferrable)
      --no-synthesize           Disable Stage 3 synthesis
      --include-chairman        Do not filter chairman out of members
      --exclude-chairman        Filter chairman out of members (default)
  -h, --help                    Show help

Environment overrides:
  COUNCIL_CONFIG                Same as --config
  COUNCIL_CHAIRMAN              Same as --chairman
  COUNCIL_CHAIRMAN_COMMAND      Same as --chairman-command
EOF
}

# Color name to code mapping
get_color_code() {
    case "$1" in
        RED) echo "$RED" ;;
        GREEN) echo "$GREEN" ;;
        BLUE) echo "$BLUE" ;;
        YELLOW) echo "$YELLOW" ;;
        CYAN) echo "$CYAN" ;;
        MAGENTA) echo "$MAGENTA" ;;
        *) echo "$NC" ;;
    esac
}

detect_host() {
    case "$SKILL_DIR" in
        */.claude/skills/*) echo "claude" ;;
        */.codex/skills/*) echo "codex" ;;
        *) echo "unknown" ;;
    esac
}

CONFIG_FILE="${COUNCIL_CONFIG:-$DEFAULT_CONFIG_FILE}"
CHAIRMAN_OVERRIDE="${COUNCIL_CHAIRMAN:-}"
CHAIRMAN_COMMAND_OVERRIDE="${COUNCIL_CHAIRMAN_COMMAND:-}"
SYNTHESIZE_OVERRIDE=""
EXCLUDE_CHAIRMAN_OVERRIDE=""

PROMPT_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --chairman)
            CHAIRMAN_OVERRIDE="$2"
            shift 2
            ;;
        --chairman-command)
            CHAIRMAN_COMMAND_OVERRIDE="$2"
            shift 2
            ;;
        --synthesize)
            SYNTHESIZE_OVERRIDE="true"
            shift
            ;;
        --no-synthesize)
            SYNTHESIZE_OVERRIDE="false"
            shift
            ;;
        --include-chairman)
            EXCLUDE_CHAIRMAN_OVERRIDE="false"
            shift
            ;;
        --exclude-chairman)
            EXCLUDE_CHAIRMAN_OVERRIDE="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            PROMPT_ARGS+=("$@")
            break
            ;;
        -*)
            echo -e "${RED}Error: Unknown option: $1${NC}" >&2
            usage >&2
            exit 2
            ;;
        *)
            PROMPT_ARGS+=("$1")
            shift
            ;;
    esac
done

if [ ${#PROMPT_ARGS[@]} -eq 0 ]; then
    echo -e "${RED}Error: Please provide a prompt${NC}" >&2
    usage >&2
    exit 1
fi

PROMPT="${PROMPT_ARGS[*]}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

# Parse YAML config (simple parser for our structure - macOS compatible)
parse_members() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Warning: Config file not found at $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}Using default configuration (codex, gemini)${NC}" >&2
        echo "codex|codex exec|🤖|BLUE"
        echo "gemini|gemini|💎|GREEN"
        return
    fi

    # Extract members using awk (macOS/BSD compatible)
    awk '
    /^  members:/ { in_members=1; next }
    /^  [a-z]/ && in_members { in_members=0 }
    in_members && /- name:/ {
        name=$3
        gsub(/"/, "", name)
    }
    in_members && /command:/ {
        cmd = $0
        sub(/.*command: *"?/, "", cmd)
        sub(/".*$/, "", cmd)
    }
    in_members && /emoji:/ {
        emoji = $2
        gsub(/"/, "", emoji)
    }
    in_members && /color:/ {
        color = $2
        gsub(/"/, "", color)
        if (name && cmd) {
            print name "|" cmd "|" emoji "|" color
            name=""; cmd=""; emoji=""; color=""
        }
    }
    ' "$CONFIG_FILE"
}

parse_chairman_role() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "auto"
        return
    fi

    awk '
    /^  chairman:/ { in_chair=1; next }
    /^  [a-z]/ && in_chair { in_chair=0 }
    in_chair && /^    (role|name):/ {
        val=$2
        gsub(/"/, "", val)
        print val
        exit
    }
    ' "$CONFIG_FILE"
}

parse_chairman_command() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi

    awk '
    /^  chairman:/ { in_chair=1; next }
    /^  [a-z]/ && in_chair { in_chair=0 }
    in_chair && /^    command:/ {
        cmd=$0
        sub(/.*command:[ \t]*/, "", cmd) # remove prefix
        sub(/[ \t]*#.*/, "", cmd) # remove comment
        sub(/[ \t]*$/, "", cmd) # trim trailing space
        if (substr(cmd, 1, 1) == "\"" && substr(cmd, length(cmd), 1) == "\"") {
            cmd = substr(cmd, 2, length(cmd)-2)
        }
        print cmd
        exit
    }
    ' "$CONFIG_FILE"
}

parse_setting_bool() {
    local key="$1"
    local default="$2"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return
    fi

    local value
    value="$(
        awk -v k="$key" '
        /^  settings:/ { in_settings=1; next }
        /^  [a-z]/ && in_settings { in_settings=0 }
        in_settings && $1 == (k ":") {
            val=$2
            gsub(/"/, "", val)
            print val
            exit
        }
        ' "$CONFIG_FILE"
    )"

    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

normalize_bool() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|y|on) echo "true" ;;
        0|false|no|n|off) echo "false" ;;
        *) echo "" ;;
    esac
}

resolve_auto_role() {
    local role="$1"
    local host="$2"
    local role_lc
    role_lc="$(echo "$role" | tr '[:upper:]' '[:lower:]')"
    if [ "$role_lc" != "auto" ] && [ -n "$role_lc" ]; then
        echo "$role_lc"
        return
    fi
    case "$host" in
        codex) echo "codex" ;;
        claude) echo "claude" ;;
        *) echo "claude" ;;
    esac
}

infer_default_chairman_command() {
    case "$1" in
        codex) echo "codex exec" ;;
        gemini) echo "gemini" ;;
        *) echo "" ;;
    esac
}

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🏛️  Agent Council - Gathering Opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📝 Question:${NC} $PROMPT"
echo ""

# Function to call an agent
call_agent() {
    local name="$1"
    local command="$2"
    local output_file="$TEMP_DIR/${name}.txt"
    local color_code="$3"
    local show_thinking="$4"

    if [ "$show_thinking" = "true" ]; then
        echo -e "${color_code}[$name]${NC} Thinking..." >&2
    fi

    # Extract the base command (first word)
    local base_cmd=$(echo "$command" | awk '{print $1}')

    if command -v "$base_cmd" &> /dev/null; then
        # Execute the command with the prompt
        eval "$command \"\$PROMPT\"" 2>/dev/null > "$output_file" || echo "Error calling $name" > "$output_file"
    else
        echo "$name CLI not installed (command: $base_cmd)" > "$output_file"
    fi

    if [ "$show_thinking" = "true" ]; then
        echo -e "${GREEN}[$name]${NC} Done" >&2
    fi
}

# Function to call chairman for synthesis
call_chairman() {
    local name="$1"
    local command="$2"
    local chairman_prompt="$3"
    local output_file="$TEMP_DIR/__chairman.txt"

    if [ -z "$command" ]; then
        echo "Chairman command not configured" > "$output_file"
        return
    fi

    local base_cmd
    base_cmd=$(echo "$command" | awk '{print $1}')
    if ! command -v "$base_cmd" &> /dev/null; then
        echo "Chairman CLI not installed (command: $base_cmd)" > "$output_file"
        return
    fi

    # Use a temp file to avoid shell quoting issues with long/multiline prompts
    local prompt_file="$TEMP_DIR/__chairman_prompt.txt"
    printf "%s" "$chairman_prompt" > "$prompt_file"

    # Most CLIs accept a prompt arg; codex exec also supports stdin via "-" but we keep it generic here.
    # Read the prompt file into a variable so we can reuse the same execution pattern as members.
    # Read the prompt file into a local variable to avoid modifying the global PROMPT variable.
    local chairman_prompt_for_eval
    chairman_prompt_for_eval="$(cat "$prompt_file")"
    eval "$command \"\$chairman_prompt_for_eval\"" 2>/dev/null > "$output_file" || echo "Error calling chairman ($name)" > "$output_file"
}

# Resolve chairman + settings
HOST="$(detect_host)"
CHAIRMAN_ROLE_RAW="${CHAIRMAN_OVERRIDE:-$(parse_chairman_role)}"
CHAIRMAN_ROLE="$(resolve_auto_role "${CHAIRMAN_ROLE_RAW:-auto}" "$HOST")"
CHAIRMAN_COMMAND="${CHAIRMAN_COMMAND_OVERRIDE:-$(parse_chairman_command)}"

EXCLUDE_CHAIRMAN_FROM_MEMBERS_RAW="${EXCLUDE_CHAIRMAN_OVERRIDE:-$(parse_setting_bool "exclude_chairman_from_members" "true")}"
EXCLUDE_CHAIRMAN_FROM_MEMBERS="$(normalize_bool "$EXCLUDE_CHAIRMAN_FROM_MEMBERS_RAW")"
if [ -z "$EXCLUDE_CHAIRMAN_FROM_MEMBERS" ]; then
    EXCLUDE_CHAIRMAN_FROM_MEMBERS="true"
fi

SHOW_THINKING_RAW="$(parse_setting_bool "show_thinking" "true")"
SHOW_THINKING="$(normalize_bool "$SHOW_THINKING_RAW")"
if [ -z "$SHOW_THINKING" ]; then
    SHOW_THINKING="true"
fi

PARALLEL_RAW="$(parse_setting_bool "parallel" "true")"
PARALLEL="$(normalize_bool "$PARALLEL_RAW")"
if [ -z "$PARALLEL" ]; then
    PARALLEL="true"
fi

SYNTHESIZE_SETTING_RAW="$(parse_setting_bool "synthesize" "")"
SYNTHESIZE_SETTING="$(normalize_bool "$SYNTHESIZE_SETTING_RAW")"
if [ -n "$SYNTHESIZE_OVERRIDE" ]; then
    SYNTHESIZE="$SYNTHESIZE_OVERRIDE"
elif [ -n "$SYNTHESIZE_SETTING" ]; then
    SYNTHESIZE="$SYNTHESIZE_SETTING"
elif [ -n "$CHAIRMAN_COMMAND" ]; then
    SYNTHESIZE="true"
else
    SYNTHESIZE="false"
fi

if [ "$SYNTHESIZE" = "true" ] && [ -z "$CHAIRMAN_COMMAND" ]; then
    CHAIRMAN_COMMAND="$(infer_default_chairman_command "$CHAIRMAN_ROLE")"
fi

# Stage 1: Collect members and call in parallel
echo -e "${YELLOW}Stage 1: Collecting opinions from council members...${NC}"
echo ""

# Read members and start parallel calls
declare -a PIDS
declare -a MEMBERS
declare -a SKIPPED

while IFS='|' read -r name cmd emoji color; do
    [ -z "$name" ] && continue
    if [ "$EXCLUDE_CHAIRMAN_FROM_MEMBERS" = "true" ] && [ "$(echo "$name" | tr '[:upper:]' '[:lower:]')" = "$CHAIRMAN_ROLE" ]; then
        SKIPPED+=("$name")
        continue
    fi
    MEMBERS+=("$name|$emoji|$color")
    color_code=$(get_color_code "$color")
    if [ "$PARALLEL" = "true" ]; then
        call_agent "$name" "$cmd" "$color_code" "$SHOW_THINKING" &
        PIDS+=($!)
    else
        call_agent "$name" "$cmd" "$color_code" "$SHOW_THINKING"
    fi
done < <(parse_members)

# Wait for all agents
if [ "$PARALLEL" = "true" ]; then
    for pid in "${PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
fi

echo ""
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}ⓘ Skipped member(s) because they are set as Chairman:${NC} ${SKIPPED[*]}"
    echo ""
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Stage 2: Council Opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Display each member's response
for member_info in "${MEMBERS[@]}"; do
    IFS='|' read -r name emoji color <<< "$member_info"
    color_code=$(get_color_code "$color")
    output_file="$TEMP_DIR/${name}.txt"

    echo -e "${color_code}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${color_code}│ ${emoji} ${name}${NC}"
    echo -e "${color_code}└─────────────────────────────────────────────────────────┘${NC}"

    if [ -f "$output_file" ]; then
        cat "$output_file"
    else
        echo "No response"
    fi
    echo ""
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$SYNTHESIZE" = "true" ] && [ -n "$CHAIRMAN_COMMAND" ]; then
    echo -e "${CYAN}Stage 3: Chairman Synthesis (via CLI)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    CHAIRMAN_PROMPT="You are the Chairman of an AI council."
    CHAIRMAN_PROMPT+=$'\n\n'"User question:"
    CHAIRMAN_PROMPT+=$'\n'"$PROMPT"
    CHAIRMAN_PROMPT+=$'\n\n'"Council member opinions:"
    for member_info in "${MEMBERS[@]}"; do
        IFS='|' read -r name emoji color <<< "$member_info"
        output_file="$TEMP_DIR/${name}.txt"
        CHAIRMAN_PROMPT+=$'\n\n'"[${name}]"
        if [ -f "$output_file" ]; then
            CHAIRMAN_PROMPT+=$'\n'"$(cat "$output_file")"
        else
            CHAIRMAN_PROMPT+=$'\n'"No response"
        fi
    done
    CHAIRMAN_PROMPT+=$'\n\n'"Please synthesize a final recommendation by:"
    CHAIRMAN_PROMPT+=$'\n'"- Calling out common ground and disagreements"
    CHAIRMAN_PROMPT+=$'\n'"- Providing a clear final answer"
    CHAIRMAN_PROMPT+=$'\n'"- Responding in the same language as the user question"

    call_chairman "$CHAIRMAN_ROLE" "$CHAIRMAN_COMMAND" "$CHAIRMAN_PROMPT"

    output_file="$TEMP_DIR/__chairman.txt"
    color_code=$(get_color_code "YELLOW")
    echo -e "${color_code}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${color_code}│ 🪑 chairman (${CHAIRMAN_ROLE})${NC}"
    echo -e "${color_code}└─────────────────────────────────────────────────────────┘${NC}"
    if [ -f "$output_file" ]; then
        cat "$output_file"
    else
        echo "No response"
    fi
    echo ""
else
    echo -e "${CYAN}Stage 3: ${CHAIRMAN_ROLE} (Chairman) will synthesize above opinions (external)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

# Cleanup
rm -rf "$TEMP_DIR"
