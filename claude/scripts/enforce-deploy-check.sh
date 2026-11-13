#!/usr/bin/env bash
# Bash · GitHub MCP 머지 PreToolUse 훅
# 운영 반영일 수 있는 머지·push 직전에 배포 전 점검 (AGENTS.md "운영 배포 전 점검") 을 강제한다.
# 대상: gh pr merge, main/master 로의 git push, mcp__github__merge_pull_request
#
# 한계: 명령 문자열만 보므로 그 머지가 실제로 운영에 나가는지는 모른다.
# 그래서 대상마다 1회만 차단하고, 운영 반영이 아니면 근거를 적고 다시 실행하게 한다.
# 같은 명령을 다시 실행하면 통과하므로, 통과했다는 사실이 점검을 했다는 뜻은 아니다.
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/claude-deploy-check"
# 명령 자리 (줄 시작 또는 ; & | ( $( 뒤) 에 나온 경우만 잡는다 — 커밋 메시지·echo 안의 문자열은 제외
COMMAND_START='(^|[;&|(]|\$\()[[:space:]]*(command[[:space:]]+)?'

input=$(cat)

tool_name=$(printf '%s' "${input}" | jq -r '.tool_name // empty')
session_id=$(printf '%s' "${input}" | jq -r '.session_id // empty')
cwd=$(printf '%s' "${input}" | jq -r '.cwd // empty')

# 점검 대상이면 대상 식별자를 출력한다 (아니면 빈 문자열)
find_target() {
  local command pr

  if [[ "${tool_name}" == "mcp__github__merge_pull_request" ]]; then
    printf '%s' "${input}" | jq -r '"\(.tool_input.owner)/\(.tool_input.repo)#\(.tool_input.pull_number // .tool_input.pullNumber)"'
    return 0
  fi

  [[ "${tool_name}" == "Bash" ]] || return 0

  command=$(printf '%s' "${input}" | jq -r '.tool_input.command // empty')

  if grep -qE "${COMMAND_START}gh[[:space:]]+pr[[:space:]]+merge" <<<"${command}"; then
    pr=$(grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[^;&|]*' <<<"${command}" | grep -oE '(https://[^[:space:]]+|[[:space:]][0-9]+)' | head -1 | tr -d '[:space:]' || true)
    printf 'pr-merge %s %s' "${cwd}" "${pr:-current-branch}"
    return 0
  fi

  if grep -qE "${COMMAND_START}git[^;&|]*[[:space:]]push[^;&|]*[[:space:]:+](main|master)([[:space:]]|\$)" <<<"${command}"; then
    printf 'push-default %s' "${cwd}"
  fi

  return 0
}

target=$(find_target)

if [[ -z "${target}" ]]; then
  exit 0
fi

# 무한 차단 방지: 세션 · 대상당 1회만 차단
state_key=$(printf '%s %s' "${session_id}" "${target}" | md5 -q)
state_file="${STATE_DIR}/${state_key}"

if [[ -f "${state_file}" ]]; then
  exit 0
fi

mkdir -p "${STATE_DIR}"
touch "${state_file}"

cat >&2 <<EOF
[배포 전 점검 게이트] 운영에 반영될 수 있는 머지·push 입니다: ${target}

운영 반영이면 실행 전에 아래를 점검하고, 사용자에게 보이는 응답에 항목별 결과 (OK · 이슈 · 미확인) 를 적으세요.
기준: ~/.dotfiles/claude/AGENTS.md "운영 배포 전 점검"

- 범위: diff 가 의도한 변경만 담는가
- CI·리뷰: CI 통과, 승인, 봇 리뷰 지적 처리
- 선행 조건: 마이그레이션·설정·시크릿·플래그·상대 API 가 운영에 준비됐는가
- 호환성: 구·신 버전 혼재, 기존 데이터·호출자와 동작하는가
- 검증 근거: dev·QA 에서 이 커밋으로 확인했는가 (못 본 항목은 미확인)
- 되돌리기: 롤백 방법·데이터 영향, 배포 후 볼 로그·지표

- 사용자가 배포를 요청했고 이슈가 없으면: 결과를 적은 뒤 같은 명령을 다시 실행
- 이슈나 미확인 항목이 있으면: 실행하지 말고 사용자에게 보고
- 사용자가 요청하지 않은 운영 반영이면: 결과와 함께 확인을 받는다
- 운영 반영이 아니면 (dev values·문서 등): 근거를 한 줄 적고 다시 실행
EOF

exit 2
