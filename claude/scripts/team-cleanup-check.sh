#!/usr/bin/env bash
# Stop 훅 — 팀 리드의 턴이 끝날 때, 할 일을 마친 팀메이트가 명단에 남아 있으면 정리를 지시한다.
#
# set -e 를 쓰지 않는 이유: Stop 훅에서 exit 2 는 "턴 차단" 이다.
# jq 실패나 파일 없음이 종료 코드로 새어 나가면 팀과 무관한 일반 세션의 턴까지 막는다.
# 예기치 못한 실패는 전부 exit 0 으로 흡수한다.
set -uo pipefail

# 스폰 직후 부팅 (tmux 페인 생성 + MCP 로딩) 유예.
# 이 구간에는 members[] 에 isActive 필드 자체가 없으므로 이중 방어다.
GRACE_SEC=600

input=$(cat)

# --- 1. 구조적 가드 (파일을 건드리기 전에 끝낸다) ---
# 구분자로 탭이 아니라 '|' 를 쓴다: bash 의 read 는 IFS 가 공백문자(탭 포함)면
# 연속된 구분자를 하나로 뭉개서 빈 필드가 밀린다. '|' 는 뭉개지지 않는다.
IFS='|' read -r session_id stop_active agent_id perm_mode bg_busy < <(
  printf '%s' "${input}" | jq -r '
    [ .session_id // "",
      (.stop_hook_active // false | tostring),
      .agent_id // "",
      .permission_mode // "",
      ((.background_tasks // [])
        | map(select(.status == "running" or .status == "pending")) | length | tostring)
    ] | join("|")' 2>/dev/null
) || exit 0

[[ "${stop_active}" == "true" ]] && exit 0   # 재진입 — 런타임이 명시적으로 요구하는 가드
[[ -n "${agent_id}" ]]          && exit 0    # 서브에이전트 / in-process 팀메이트 컨텍스트
[[ "${perm_mode}" == "plan" ]]  && exit 0    # 계획 모드에선 TaskStop 을 실행할 수 없다
[[ "${bg_busy}" != "0" ]]       && exit 0    # 아직 도는 백그라운드 작업이 있다
[[ -n "${session_id}" ]]        || exit 0

# --- 2. 이 세션이 팀 리드인가 ---
# 팀 디렉토리명은 리드 세션 ID 앞 8자에서 파생된다 (session-<8자>). 전체 스캔이 필요 없다.
teams_root="${CLAUDE_TEAMS_ROOT:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/teams}"
config="${teams_root}/session-${session_id:0:8}/config.json"

[[ -f "${config}" ]] || exit 0

# --- 3. 정리 대상 = 리드 제외 + isActive 가 '명시적 false' + 부팅 유예 경과 ---
# isActive 는 3-상태다: 필드 없음 (부팅 중) / true (작업 중) / false (자기 턴을 마침).
# jq 에서 필드가 없으면 null 이고 null == false 는 거짓이므로, 부팅 중인 팀메이트는 걸리지 않는다.
cutoff_ms=$(( ($(date +%s) - GRACE_SEC) * 1000 ))

stale=$(jq -r --argjson cutoff "${cutoff_ms}" '
  (.leadAgentId // "") as $lead
  | .members[]?
  | select(.agentId != $lead)
  | select(.isActive == false)
  | select((.joinedAt // 0) < $cutoff)
  | .name' "${config}" 2>/dev/null) || exit 0

[[ -n "${stale}" ]] || exit 0

# --- 4. 같은 명단으로 이미 알렸으면 통과 (반복 차단 방지) ---
state_dir="${TMPDIR:-/tmp}/claude-team-cleanup"
state_file="${state_dir}/$(printf '%s|%s' "${session_id}" "${stale}" | md5 -q)"

[[ -f "${state_file}" ]] && exit 0

mkdir -p "${state_dir}" && touch "${state_file}"

# 오발동 사후 진단용 — 언제 어떤 이름으로 울렸는지 남긴다
printf '%s\t%s\t%s\n' \
  "$(date -Iseconds)" "${session_id}" "$(printf '%s' "${stale}" | tr '\n' ',')" \
  >> "${state_dir}/fired.log"

# --- 5. 정리 지시 ---
{
  echo "[팀 정리] 아래 팀메이트는 자기 턴을 마치고 대기 중입니다. 명단에 남겨두면 창과 컨텍스트만 차지합니다."
  echo
  while IFS= read -r name; do printf '  - %s\n' "${name}"; done <<< "${stale}"
  echo
  echo "산출물을 이미 종합했다면 각각 TaskStop(task_id: \"<이름>\") 으로 정리하세요."
  echo "더 시킬 일이 있으면 새로 띄우지 말고 SendMessage({to: \"<이름>\"}) 로 재지시하세요."
  echo "이미 사라진 이름이면 그냥 넘어가세요."
  echo
  echo "아직 결과를 기다리는 중이거나 계획 승인 대기 중이라면, 이 메시지를 무시하고 하던 일을 계속하세요."
  echo "편성/해산 기준: ~/.claude/docs/team-mode.md"
} >&2

exit 2
