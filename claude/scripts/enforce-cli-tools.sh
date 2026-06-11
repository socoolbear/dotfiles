#!/usr/bin/env bash
# PreToolUse(Bash) hook — 표준 CLI (grep/find/cat/ls) 사용을 차단하고 모던 대체 도구를 안내
# 규칙: claude/rules/cli-tools.md (대체 도구 미설치 시엔 차단하지 않고 폴백 허용)
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"${input}" 2>/dev/null) || exit 0

if [[ -z "${cmd}" ]]; then
  exit 0
fi

nl=$'\n'
reasons=""

# 명령 위치 (문자열 시작, 파이프/체인/서브셸 직후) 의 도구만 매칭 — git grep, lsof 등은 통과
matches_command_position() {
  local tool="$1"
  local pattern="(^|[|;&(\`${nl}])[[:space:]]*${tool}([^[:alnum:]_.-]|$)"

  [[ "${cmd}" =~ ${pattern} ]]
}

# 대체 도구가 설치된 경우에만 차단 사유 추가 ("-" 는 항상 차단)
collect_reason() {
  local legacy="$1" replacement="$2" message="$3"

  matches_command_position "${legacy}" || return 0

  if [[ "${replacement}" != "-" ]] && ! command -v "${replacement}" >/dev/null 2>&1; then
    return 0
  fi

  reasons="${reasons}${reasons:+ / }${message}"
}

collect_reason grep rg  "grep 대신 rg"
collect_reason find fd  "find 대신 fd"
collect_reason cat  -   "cat 대신 Read 도구 (파이프라인 내에선 bat)"
collect_reason ls   eza "ls 대신 eza"

if [[ -z "${reasons}" ]]; then
  exit 0
fi

jq -n --arg reason "CLI 도구 규칙 (claude/rules/cli-tools.md): ${reasons} 를 사용하세요. 불가피한 경우에만 'command <도구>' 형태로 우회하세요." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
