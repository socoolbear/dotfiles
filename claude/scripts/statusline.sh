#!/bin/bash

# Claude Code Status Line Script
# Displays: Model | Directory | Git Branch & Status | Tokens | MCP Servers

# ANSI Color Codes
CYAN='\033[36m'
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Read JSON from stdin
json=$(cat)

# Parse JSON using jq
model=$(echo "$json" | jq -r '.model.display_name // "Unknown"')
current_dir=$(echo "$json" | jq -r '.workspace.current_dir // ""')
context_pct=$(echo "$json" | jq -r '.context_window.used_percentage // 0')
context_window_size=$(echo "$json" | jq -r '.context_window.context_window_size // 200000')

# Calculate used tokens from current_usage
input_tokens=$(echo "$json" | jq -r '.context_window.current_usage.input_tokens // 0')
output_tokens=$(echo "$json" | jq -r '.context_window.current_usage.output_tokens // 0')
cache_creation=$(echo "$json" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$json" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
used_tokens=$((input_tokens + output_tokens + cache_creation + cache_read))

# Get directory basename
if [ -n "$current_dir" ]; then
    dir_name=$(basename "$current_dir")
else
    dir_name=$(basename "$(pwd)")
fi

# Get Git info if in a git repository
git_info=""
if [ -n "$current_dir" ] && [ -d "$current_dir/.git" ] || git -C "${current_dir:-.}" rev-parse --git-dir > /dev/null 2>&1; then
    if cd "${current_dir:-.}" 2>/dev/null; then
        branch=$(git branch --show-current 2>/dev/null)
        if [ -n "$branch" ]; then
            # Count staged, modified, and untracked files
            staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
            modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
            untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

            git_status=""
            [ "$staged" -gt 0 ] && git_status+=" ${YELLOW}✚${staged}${RESET}"
            [ "$modified" -gt 0 ] && git_status+=" ${YELLOW}✱${modified}${RESET}"
            [ "$untracked" -gt 0 ] && git_status+=" ${YELLOW}◌${untracked}${RESET}"

            git_info=" | ${GREEN}🌿 ${branch}${RESET}${git_status}"
        fi
    fi
fi

# Format tokens (K for thousands)
format_tokens() {
    local tokens=$1
    if [ "$tokens" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $tokens / 1000000" | bc)"
    elif [ "$tokens" -ge 1000 ]; then
        printf "%.1fK" "$(echo "scale=1; $tokens / 1000" | bc)"
    else
        printf "%d" "$tokens"
    fi
}

used_fmt=$(format_tokens "$used_tokens")
total_fmt=$(format_tokens "$context_window_size")
remaining_tokens=$((context_window_size - used_tokens))
remaining_fmt=$(format_tokens "$remaining_tokens")

# Determine context color based on percentage
context_int=${context_pct%.*}
if [ "$context_int" -le 50 ]; then
    context_color=$GREEN
elif [ "$context_int" -le 80 ]; then
    context_color=$YELLOW
else
    context_color=$RED
fi

# Build output
output="${CYAN}[${model}]${RESET}"
output+=" ${BLUE}📁 ${dir_name}${RESET}"
output+="${git_info}"
output+=" | ${context_color}🔤 ${used_fmt}/${total_fmt} (${remaining_fmt} left)${RESET}"

echo -e "$output"
