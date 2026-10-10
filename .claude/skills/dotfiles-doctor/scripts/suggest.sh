#!/usr/bin/env bash
# SessionStart 훅: doctor 를 돌릴 때가 됐으면 제안만 한다 (실행은 사용자가 정한다 — 2026-10-09 사용자 결정)
# 조건: 마지막 doctor: 커밋 이후 Claude Code 버전 변경 · 30일 경과 · doctor.sh FAIL
set -uo pipefail

repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "${repo}" || exit 0

maxDays=30
reasons=()

lastCommit=$(git log --format='%h%x09%s' | awk -F'\t' 'index($2,"doctor:")==1{print $1; exit}')
currentVersion=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

if [[ -z "${lastCommit}" ]]; then
  reasons+=("doctor 실행 기록 (doctor: 커밋) 이 없음")
else
  ageDays=$(( ( $(date +%s) - $(git log -1 --format=%ct "${lastCommit}") ) / 86400 ))
  [[ ${ageDays} -ge ${maxDays} ]] && reasons+=("마지막 실행 (${lastCommit}) 이후 ${ageDays}일 경과")

  # doctor 커밋 본문의 'Claude Code: x.y.z' 줄이 기준 버전 (SKILL.md 6단계). 줄이 없으면 버전 조건은 건너뛴다
  doctorVersion=$(git log -1 --format=%b "${lastCommit}" | grep -oE '^Claude Code: [0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9.]+$')
  if [[ -n "${doctorVersion}" && -n "${currentVersion}" && "${doctorVersion}" != "${currentVersion}" ]]; then
    reasons+=("Claude Code 버전 변경 (${doctorVersion} → ${currentVersion})")
  fi
fi

failCount=$(DOTFILES="${repo}" bash .claude/skills/dotfiles-doctor/scripts/doctor.sh 2>/dev/null | grep -c '^\[FAIL\]')
[[ ${failCount} -gt 0 ]] && reasons+=("doctor.sh FAIL ${failCount}건")

[[ ${#reasons[@]} -eq 0 ]] && exit 0

joined=$(printf '%s · ' "${reasons[@]}")
joined="${joined% · }"
message="dotfiles-doctor 실행을 제안합니다: ${joined}. 'dotfiles 점검해줘' 로 실행할 수 있어요."

jq -n --arg m "${message}" '{
  systemMessage: $m,
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("[doctor 제안] " + $m + " 첫 응답에서 사용자에게 한 줄로 알리고, 실행은 사용자가 요청할 때만 한다.")
  }
}'
