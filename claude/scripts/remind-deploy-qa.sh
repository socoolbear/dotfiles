#!/usr/bin/env bash
# Bash PostToolUse 훅 — 배포를 일으키는 명령이 실행된 직후 "직접 QA" 를 알린다 (2026-11-18 사용자 지시).
# 기준: AGENTS.md "배포 확인 지점 > 배포 뒤 직접 QA", 상세는 docs/workflow.md §4.
#
# enforce-deploy-check.sh 는 실행 전 점검을 맡고 FTP·kubectl 같은 수동 배포는 잡지 않는다.
# 이 훅은 실행 뒤 알림만 하므로 넓게 잡는다 — 잘못 잡혀도 알림 한 줄이 더 나올 뿐이다.
#
# set -e 를 쓰지 않는 이유: 모든 Bash 호출 뒤에 도는 훅이라 실패가 작업 흐름을 깨면 안 된다. 실패는 exit 0 으로 흡수한다.
set -uo pipefail

# 명령 자리 (줄 시작 또는 ; & | ( $( 뒤) 에 나온 경우만 잡는다 — 커밋 메시지·echo 안의 문자열을 빼려는 것 (완전하지 않다)
COMMAND_START='(^|[;&|(]|\$\()[[:space:]]*'
DEPLOY_PATTERNS=(
  "${COMMAND_START}gh[[:space:]]+pr[[:space:]]+merge"
  "${COMMAND_START}gh[[:space:]]+workflow[[:space:]]+run"
  "${COMMAND_START}gh[[:space:]]+api[[:space:]].*/dispatches"
  "${COMMAND_START}git[[:space:]]+push[[:space:]].*(main|master|dev|develop|stage|staging)([[:space:]]|$)"
  "ftp-upload\.sh[[:space:]].*--apply"
  "${COMMAND_START}(kubectl[[:space:]]+(apply|rollout|set[[:space:]]+image)|helm[[:space:]]+(upgrade|install|rollback)|argocd[[:space:]]+app[[:space:]]+sync)"
  "${COMMAND_START}(vercel|netlify|firebase|wrangler|fly|flyctl|serverless|sls|cdk|eb)[[:space:]]+(.*[[:space:]])?deploy"
  "${COMMAND_START}terraform[[:space:]]+apply"
)

input=$(cat)
command_text=$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "${command_text}" ]] && exit 0

is_deploy_command() {
  local pattern

  for pattern in "${DEPLOY_PATTERNS[@]}"; do
    if [[ "${command_text}" =~ ${pattern} ]]; then
      return 0
    fi
  done

  return 1
}

is_deploy_command || exit 0

message='[배포 뒤 직접 QA] 방금 명령이 배포를 일으켰다면 (dev·stage·prod, 수동 업로드 포함) 묻지 않고 직접 QA 한다 (AGENTS.md "배포 뒤 직접 QA", 2026-11-18 사용자 지시).
- 직접 QA = 배포된 것을 쓰는 사람의 경로로 실제 써 보는 것: 화면은 브라우저로 열어 조작, API 는 실제 호출과 응답 내용, 배치·컨슈머는 실행 결과와 로그. 응답 코드·크기만 본 것은 QA 가 아니다.
- 묻는 경우는 셋뿐: 직접 할 수단이 없을 때 (계정·권한·2단계 인증·환경), 보안이 걸릴 때 (비밀 값·남의 계정·개인정보), 위험이 큰 동작일 때 (운영 데이터 쓰기·결제·주문·외부 발송 등 되돌리기 어려운 것). 그때도 할 수 있는 부분은 먼저 하고 남은 것만 묻는다.
- 보고에 QA 방법 (브라우저·호출·로그) 과 본 것·못 본 것 (미확인) 을 나눠 적는다. 배포가 아니었으면 이 알림은 무시한다.'

jq -n --arg msg "${message}" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}' 2>/dev/null

exit 0
