#!/usr/bin/env bash
# SessionStart 훅 (matcher: compact) — 자동 compact 직후, 진행 문서와 작업 상태를 컨텍스트에 복원한다.
#
# set -e 를 쓰지 않는 이유: 복원이 실패해도 세션 시작을 막으면 안 된다.
# 예기치 못한 실패는 전부 exit 0 으로 흡수한다.
set -uo pipefail

MAX_CHARS=8000   # additionalContext 상한 (훅 출력 제한 10000자 안쪽)

input=$(cat)

# --- 1. 구조적 가드 ---
IFS='|' read -r agent_id session_id transcript_path cwd < <(
  printf '%s' "${input}" | jq -r '
    [ .agent_id // "",
      .session_id // "",
      .transcript_path // "",
      .cwd // ""
    ] | join("|")' 2>/dev/null
) || exit 0

[[ -n "${agent_id}" ]]   && exit 0   # 서브에이전트 컨텍스트
[[ -n "${session_id}" ]] || exit 0

# --- 2. context-guard 상태 초기화 (compact 후 50% / 80% 알림이 다시 나가도록) ---
rm -f "${TMPDIR:-/tmp}/claude-context-guard/${session_id}" 2>/dev/null

# --- 3. 복원 본문 조립 (진행 문서를 앞에 둬서 절단돼도 핵심이 남게 한다) ---
project_dir="${CLAUDE_PROJECT_DIR:-${cwd}}"
progress_file="${project_dir}/.prompts/PROGRESS-${session_id:0:8}.md"

body="[compact 복원] 자동 compact 직후입니다. 아래 진행 문서로 작업을 이어가세요."$'\n'

if [[ -f "${progress_file}" ]]; then
  modified=$(stat -f '%Sm' "${progress_file}" 2>/dev/null)
  body+=$'\n'"## 진행 문서 (${progress_file}, 수정: ${modified})"$'\n'
  body+="$(cat "${progress_file}" 2>/dev/null)"$'\n'
else
  body+=$'\n'"진행 문서 없음 — compact 요약을 기준으로 진행하고, 이어서 진행 문서(${progress_file})를 새로 작성하라."$'\n'
fi

if [[ -d "${project_dir}" ]] && git -C "${project_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_status=$(git -C "${project_dir}" status --short 2>/dev/null | head -30)
  body+=$'\n'"## git status (${project_dir})"$'\n'"${git_status:-(변경 없음)}"$'\n'
fi

if [[ -n "${transcript_path}" ]]; then
  body+=$'\n'"## compact 전 원문"$'\n'"${transcript_path} — compact 전 상세가 필요하면 이 파일을 grep 하라."$'\n'
fi

# --- 4. 절단 후 출력 ---
body="${body:0:${MAX_CHARS}}"

jq -n --arg msg "${body}" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}' 2>/dev/null

exit 0
