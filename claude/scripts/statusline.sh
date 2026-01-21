#!/bin/bash

# Claude Code Status Line Script (Agnoster-style)
# Displays: User@Host | Directory | Git Branch & Status | Model | Tokens

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

# Get current directory
if [ -n "$current_dir" ]; then
    dir_path="${current_dir/#$HOME/~}"
else
    dir_path="${PWD/#$HOME/~}"
fi

# Get MCP server count
mcp_count=0
if [ -f "$HOME/.claude.json" ]; then
    user_mcp=$(jq '.mcpServers | length' "$HOME/.claude.json" 2>/dev/null || echo 0)
    mcp_count=$((mcp_count + user_mcp))
fi
if [ -n "$current_dir" ] && [ -f "$current_dir/.mcp.json" ]; then
    proj_mcp=$(jq '.mcpServers | length' "$current_dir/.mcp.json" 2>/dev/null || echo 0)
    mcp_count=$((mcp_count + proj_mcp))
fi

# Format MCP info
if [ "$mcp_count" -gt 0 ]; then
    mcp_info="🔌 $mcp_count"
else
    mcp_info="🔌 0"
fi

# Get Git info if in a git repository
git_info=""
if [ -n "$current_dir" ] && [ -d "$current_dir/.git" ] || git -C "${current_dir:-.}" rev-parse --git-dir > /dev/null 2>&1; then
    if cd "${current_dir:-.}" 2>/dev/null; then
        branch=$(git branch --show-current 2>/dev/null)
        if [ -n "$branch" ]; then
            # Check if working directory is clean
            if git diff-index --quiet HEAD -- 2>/dev/null; then
                # Clean status
                git_info=$(printf " \033[32m⎇ %s\033[0m" "$branch")
            else
                # Dirty status
                git_info=$(printf " \033[33m⎇ %s ±\033[0m" "$branch")
            fi
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
    context_color=$'\033[32m'  # Green
elif [ "$context_int" -le 80 ]; then
    context_color=$'\033[33m'  # Yellow
else
    context_color=$'\033[31m'  # Red
fi

# Build output (dir [git] | model | mcp | tokens)
printf "\033[34m%s\033[0m%s | \033[35m%s\033[0m | \033[36m%s\033[0m | %s%s/%s (%s left)\033[0m" \
    "$dir_path" "$git_info" "$model" "$mcp_info" "$context_color" "$used_fmt" "$total_fmt" "$remaining_fmt"
