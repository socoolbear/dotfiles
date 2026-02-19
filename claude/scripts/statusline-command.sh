#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

cwd=$(echo "${input}" | jq -r '.cwd')
model=$(echo "${input}" | jq -r '.model.display_name')
used_pct=$(echo "${input}" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "${input}" | jq -r '.vim.mode // empty')

# ~로 홈 디렉토리 축약
home="${HOME}"
display_dir="${cwd/#${home}/\~}"

# git 브랜치 (선택적 잠금 무시)
git_branch=""
if git -C "${cwd}" rev-parse --is-inside-work-tree --no-optional-locks 2>/dev/null | grep -q true; then
  git_branch=$(git -C "${cwd}" symbolic-ref --short HEAD 2>/dev/null || git -C "${cwd}" rev-parse --short HEAD 2>/dev/null || echo "")
fi

# ANSI 색상 (ANSI-C quoting 으로 실제 이스케이프 바이트 저장)
RESET=$'\033[0m'
BOLD=$'\033[1m'
BLUE=$'\033[34m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'

# user@host
user_host="$(whoami)@$(hostname -s)"

# 컨텍스트 사용량
ctx_info=""
if [[ -n "${used_pct}" ]]; then
  ctx_int=${used_pct%.*}
  if [[ "${ctx_int}" -ge 80 ]]; then
    ctx_color=$'\033[31m'  # red
  elif [[ "${ctx_int}" -ge 50 ]]; then
    ctx_color=$'\033[33m'  # yellow
  else
    ctx_color="${GREEN}"
  fi
  ctx_info=" ${ctx_color}ctx:${used_pct}%${RESET}"
fi

# vim 모드
vim_info=""
if [[ -n "${vim_mode}" ]]; then
  vim_info=" ${MAGENTA}[${vim_mode}]${RESET}"
fi

# git 브랜치 표시
git_info=""
if [[ -n "${git_branch}" ]]; then
  git_info=" ${GREEN} ${git_branch}${RESET}"
fi

printf "${BOLD}${CYAN}%s${RESET} ${BLUE}%s${RESET}%s%s%s ${YELLOW}%s${RESET}" \
  "${user_host}" \
  "${display_dir}" \
  "${git_info}" \
  "${ctx_info}" \
  "${vim_info}" \
  "${model}"
