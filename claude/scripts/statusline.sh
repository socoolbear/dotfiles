#!/bin/bash

# Claude Code Status Line Script
# Displays: Model | Directory | Git Branch & Status | Cost | Context Usage

# ANSI Color Codes
CYAN='\033[36m'
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
RED='\033[31m'
RESET='\033[0m'

# Read JSON from stdin
json=$(cat)

# Parse JSON using jq
model=$(echo "$json" | jq -r '.model.display_name // "Unknown"')
current_dir=$(echo "$json" | jq -r '.workspace.current_dir // ""')
cost=$(echo "$json" | jq -r '.cost.total_cost_usd // 0')
context_pct=$(echo "$json" | jq -r '.context_window.used_percentage // 0')

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

# Format cost (show 2-4 decimal places depending on value)
if (( $(echo "$cost < 0.01" | bc -l) )); then
    cost_fmt=$(printf "%.4f" "$cost")
else
    cost_fmt=$(printf "%.2f" "$cost")
fi

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
output+=" | ${MAGENTA}💰 \$${cost_fmt}${RESET}"
output+=" | ${context_color}📊 ${context_int}%${RESET}"

echo -e "$output"
