#!/usr/bin/env bash
# Claude Code 훅 → tmux pane 옵션으로 작업 상태를 기록한다.
# tmux 하단 창 목록이 이 옵션을 읽어 창마다 스피너(작업 중) · 🔔(입력 대기) · ✅(끝났는데 아직 안 봄) 을 띄운다.
# 표시 포맷은 tmux/tmux.conf.local 의 @claude_* 옵션 참조.
#
# pane 옵션
#   @claude_state  busy | wait | done | (없음)   — 메인 세션의 상태
#   @claude_agents 실행 중인 서브에이전트 수        — 메인이 멈춰도 백그라운드 에이전트가 돌면 작업 중으로 본다
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

# 창 전환 시 그 창의 ✅ 를 지운다 (tmux 훅에서 호출, 인자로 window_id)
if [[ "${event}" == "clear-done" ]]; then
  tmuxCmd list-panes -t "${2:-}" -F '#{pane_id} #{@claude_state}' \
    | while read -r paneId state; do
        [[ "${state}" == "done" ]] && tmuxCmd set -pu -t "${paneId}" @claude_state
      done
  exit 0
fi

[[ -n "${TMUX_PANE:-}" ]] || exit 0

setState() {
  tmuxCmd set -p -t "${TMUX_PANE}" @claude_state "$1"
}

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
    ;;
  idle)
    # idle_prompt 알림 (입력 없이 일정 시간 경과): ESC 중단처럼 Stop 이 오지 않아 남은 busy/wait 를 정리
    current=$(tmuxCmd display -p -t "${TMUX_PANE}" '#{@claude_state}')

    [[ "${current}" == "busy" || "${current}" == "wait" ]] && tmuxCmd set -pu -t "${TMUX_PANE}" @claude_state
    ;;
  agent-start)
    # set -F 는 tmux 서버 안에서 한 번에 계산되므로 서브에이전트가 동시에 떠도 증감이 꼬이지 않는다
    tmuxCmd set -pF -t "${TMUX_PANE}" @claude_agents '#{e|+:#{?@claude_agents,#{@claude_agents},0},1}'
    ;;
  agent-stop)
    tmuxCmd set -pF -t "${TMUX_PANE}" @claude_agents '#{?#{e|>:#{?@claude_agents,#{@claude_agents},0},1},#{e|-:#{@claude_agents},1},0}'
    ;;
  reset)
    tmuxCmd set -pu -t "${TMUX_PANE}" @claude_state
    tmuxCmd set -pu -t "${TMUX_PANE}" @claude_agents
    ;;
esac

exit 0
