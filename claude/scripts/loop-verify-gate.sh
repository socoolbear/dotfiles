#!/usr/bin/env bash
# Stop 훅 — 야간 모드 세션이 일을 끝내려 할 때 검증 명령을 돌려, 실패하면 끝내지 못하게 막는다 (검증 게이트).
#
# 검증 명령은 사용자가 태스크 notes.md 의 "## 루프" 절에 적고 claude-loop 가 승인된 값만 넘긴다.
#   - 기존 세션: 상태 파일 ~/.local/state/claude-loop/night/<session_id> 의 JSON .verify
#   - 러너가 새로 연 세션: 환경변수 CLAUDE_NIGHT_VERIFY (CLAUDE_NIGHT=1 이고 사람이 돌아와 풀지 않았을 때)
# 밤마다 세션당 3번까지만 막는다 (런타임 상한 8회보다 먼저 끝내 질문 대기열에 남기게).
# 검증이 오래 걸릴 수 있어 settings.json 의 이 훅 항목에 timeout 을 따로 둔다.
#
# set -e 를 쓰지 않는 이유: Stop 훅의 exit 2 는 턴 차단이다. 예기치 못한 실패가 새어 나가면 일반 세션의 턴을 막는다.
set -uo pipefail

NIGHT_DIR="${HOME}/.local/state/claude-loop/night"
MAX_BLOCKS=3

input=$(cat)

IFS='|' read -r session_id cwd agent_id < <(
  jq -r '[.session_id // "", .cwd // "", .agent_id // ""] | join("|")' <<<"${input}" 2>/dev/null
) || exit 0

[[ -n "${session_id}" ]] || exit 0
[[ -z "${agent_id}" ]] || exit 0   # 서브에이전트의 종료는 검증하지 않는다

state_file="${NIGHT_DIR}/${session_id}"
blocks_file="${NIGHT_DIR}/blocks/${session_id}"
verify=""

if [[ -f "${state_file}" ]]; then
  verify=$(jq -r '.verify // ""' "${state_file}" 2>/dev/null)
elif [[ "${CLAUDE_NIGHT:-}" == "1" && -f "${NIGHT_DIR}/active" && ! -f "${NIGHT_DIR}/released/${session_id}" ]]; then
  verify="${CLAUDE_NIGHT_VERIFY:-}"
fi

[[ -n "${verify}" ]] || exit 0

blocks=$(cat "${blocks_file}" 2>/dev/null || echo 0)

[[ "${blocks}" =~ ^[0-9]+$ ]] || blocks=0
(( blocks < MAX_BLOCKS )) || exit 0

output=$(cd "${cwd:-.}" && bash -c "${verify}" 2>&1)

if [[ $? -eq 0 ]]; then
  exit 0
fi

mkdir -p "${NIGHT_DIR}/blocks" && echo $((blocks + 1)) >"${blocks_file}"

jq -n --arg tail "$(tail -n 40 <<<"${output}")" --arg cmd "${verify}" --arg n "$((blocks + 1))/${MAX_BLOCKS}" '{
  decision: "block",
  reason: ("[야간 검증 게이트 \($n)] 검증 명령 `\($cmd)` 이 실패했다. 테스트를 지우거나 고쳐서 통과시키지 말고 원인을 고쳐라. 3회째도 실패하면 고치지 말고 질문 대기열과 야간 결과에 남기고 끝내라.\n\n" + $tail)
}'
