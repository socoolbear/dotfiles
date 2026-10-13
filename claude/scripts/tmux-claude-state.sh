#!/usr/bin/env bash
# Claude Code 훅 → tmux pane 옵션으로 작업 상태를 기록한다.
# tmux 하단 창 목록이 이 옵션을 읽어 창마다 스피너(작업 중) · 🔔(입력 대기) · ✅(끝났는데 아직 안 봄) 을 띄운다.
# 표시 포맷은 tmux/tmux.conf.local 의 @claude_* 옵션 참조.
#
# pane 옵션
#   @claude_state  busy | wait | done | (없음)   — 메인 에이전트의 상태
#   @claude_agents " <agent_id> <agent_id>"      — 지금 일하고 있는 서브에이전트 · 팀메이트 목록
#   @claude_bg     실행 중인 백그라운드 셸 수     — 에이전트가 셸에 일을 맡기고 대기 중일 때 (Stop · SubagentStop 입력의 background_tasks)
#
# 훅 입력에 agent_id 가 있으면 서브에이전트 · 팀메이트의 이벤트다. 메인 상태와 섞지 않고 목록만 고친다.
# 개수를 세지 않고 ID 목록을 쓰는 이유: 팀메이트는 턴이 끝날 때마다 SubagentStop 이 오지만
# 메시지를 받아 다시 일할 때 SubagentStart 는 다시 오지 않는다 (2.1.296 에서 확인). 그래서 도구 호출 때마다
# 목록에 다시 넣고 (같은 ID 는 한 번만), SubagentStop 때 뺀다.
#
# 팀 에이전트를 split pane 으로 띄우면 각자 별도 claude 프로세스라 자기 pane 에 기록하고,
# 창 표시는 창 안의 모든 pane 을 모아 판단한다.
#
# 모든 실패는 exit 0 으로 흡수한다 (훅 실패가 작업 흐름을 깨면 안 된다).
set -uo pipefail

event="${1:-}"

tmuxCmd() {
  command tmux "$@" 2>/dev/null
}

# 창 전환 시 그 창의 ✅ 를 지운다 (tmux 훅에서 호출, 인자로 window_id — stdin 은 읽지 않는다)
if [[ "${event}" == "clear-done" ]]; then
  tmuxCmd list-panes -t "${2:-}" -F '#{pane_id} #{@claude_state}' \
    | while read -r paneId state; do
        [[ "${state}" == "done" ]] && tmuxCmd set -pu -t "${paneId}" @claude_state
      done
  exit 0
fi

[[ -n "${TMUX_PANE:-}" ]] || exit 0

input=$(cat)

# 구분자로 '|' 를 쓴다: IFS 가 공백문자면 빈 필드가 뭉개져 밀린다.
# liveAgents: 아직 살아 있는 백그라운드 에이전트 · 팀메이트 수 (Stop 입력의 background_tasks, 셸·모니터 제외)
# bgShells: 실행 중인 백그라운드 셸 수 (background_tasks 가 없는 이벤트는 빈 값)
IFS='|' read -r agentId liveAgents bgShells < <(
  printf '%s' "${input}" | jq -r '
    [ (.agent_id // "" | gsub("[^A-Za-z0-9_-]"; "")),
      ([.background_tasks[]? | select(.status == "running" and (.type | test("shell|bash|monitor") | not))] | length),
      (if has("background_tasks") then [.background_tasks[] | select(.status == "running" and (.type | test("shell|bash")))] | length else "" end) ]
    | join("|")' 2>/dev/null
)

setState() {
  tmuxCmd set -p -t "${TMUX_PANE}" @claude_state "$1"
}

# set -F 는 tmux 서버 안에서 한 번에 계산되므로 여러 에이전트가 동시에 고쳐도 꼬이지 않는다
addAgent() {
  tmuxCmd set -pF -t "${TMUX_PANE}" @claude_agents "#{s/ ${agentId}//:@claude_agents} ${agentId}"
}

removeAgent() {
  tmuxCmd set -pF -t "${TMUX_PANE}" @claude_agents "#{s/ ${agentId}//:@claude_agents}"
}

# background_tasks 가 있는 이벤트 (Stop · SubagentStop) 마다 셸 수를 갱신한다. 세션 전체 목록이라 마지막 값이 최신이다
if [[ -n "${bgShells}" ]]; then
  tmuxCmd set -p -t "${TMUX_PANE}" @claude_bg "${bgShells}"
fi

# 서브에이전트 · 팀메이트의 이벤트
if [[ -n "${agentId}" ]]; then
  case "${event}" in
    agent-stop) removeAgent ;;
    *) addAgent ;;
  esac
  exit 0
fi

# 메인 에이전트의 이벤트
case "${event}" in
  busy)
    setState busy
    ;;
  wait)
    setState wait
    ;;
  stop)
    # 지금 보고 있는 창이면 ✅ 없이 바로 비운다
    watching=$(tmuxCmd display -p -t "${TMUX_PANE}" '#{&&:#{window_active},#{session_attached}}')

    if [[ "${watching}" == "1" ]]; then
      tmuxCmd set -pu -t "${TMUX_PANE}" @claude_state
    else
      setState done
    fi

    # 살아 있는 에이전트가 하나도 없으면 목록을 비운다 (SubagentStop 을 놓친 경우의 안전장치)
    [[ "${liveAgents:-0}" == "0" ]] && tmuxCmd set -pu -t "${TMUX_PANE}" @claude_agents
    ;;
  idle)
    # idle_prompt 알림 (입력 없이 일정 시간 경과): ESC 중단처럼 Stop 이 오지 않아 남은 busy/wait 를 정리
    current=$(tmuxCmd display -p -t "${TMUX_PANE}" '#{@claude_state}')

    [[ "${current}" == "busy" || "${current}" == "wait" ]] && tmuxCmd set -pu -t "${TMUX_PANE}" @claude_state
    ;;
  reset)
    tmuxCmd set -pu -t "${TMUX_PANE}" @claude_state
    tmuxCmd set -pu -t "${TMUX_PANE}" @claude_agents
    tmuxCmd set -pu -t "${TMUX_PANE}" @claude_bg
    ;;
esac

exit 0
