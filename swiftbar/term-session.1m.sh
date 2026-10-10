#!/bin/bash
#
# SwiftBar 플러그인 — term-session (Ghostty·tmux·claude 작업 환경 저장·복원).
# 1m = 1 분마다 재실행해 마지막 저장 시각을 갱신한다.
# 메뉴의 동작은 이 파일을 "act <동작>" 인자로 다시 실행하고, 결과는 알림과 "마지막 결과" 하위 메뉴로 보여 준다.

export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin

TERM_SESSION="${HOME}/.local/bin/term-session"
STATE_DIR="${HOME}/.local/state/term-session"
SNAPSHOT="${STATE_DIR}/snapshot.json"
STALE_SECONDS=86400

notify() {
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "term-session" "$1" >/dev/null
}

confirmRestart() {
  osascript -e 'display dialog "모든 tmux 세션의 claude 와 빈 셸 pane 을 제자리에서 다시 띄울까요?\n(작업 중인 claude 와 다른 프로그램 pane 은 건너뜀)" buttons {"취소", "재시작"} default button "취소" with title "term-session"' \
    2>/dev/null | grep -q '재시작'
}

if [ "$1" = "act" ]; then
  action=$2

  if [ "${action}" = "restart" ] && ! confirmRestart; then
    exit 0
  fi

  if "${TERM_SESSION}" run "${action}" >/dev/null 2>&1; then
    case "${action}" in
      save) notify "저장 완료 — $("${TERM_SESSION}" status)" ;;
      preview) notify "미리보기 완료 — 메뉴의 '마지막 결과' 에서 확인" ;;
      *) notify "${action} 완료 — 메뉴의 '마지막 결과' 에서 확인" ;;
    esac
  else
    notify "${action} 실패 — 메뉴의 '마지막 결과' 에서 확인"
  fi
  exit 0
fi

if [ ! -x "${TERM_SESSION}" ]; then
  echo ":exclamationmark.triangle: | sfcolor=red"
  echo "---"
  echo "term-session 미설치 — make sync | color=red"
  exit 0
fi

# 저장 기록이 없거나 하루가 지났으면 강조해 재부팅 전 저장을 잊지 않게 한다
color=gray
if [ ! -f "${SNAPSHOT}" ] || [ $(( $(date +%s) - $(jq -r '.savedEpoch' "${SNAPSHOT}") )) -gt ${STALE_SECONDS} ]; then
  color=orange
fi

echo ":square.stack.3d.up: | sfcolor=${color}"
echo "---"
echo "$("${TERM_SESSION}" status) | color=${color}"
echo "---"
echo "지금 저장 | shell=$0 param1=act param2=save terminal=false refresh=true"
echo "복원 | shell=$0 param1=act param2=restore terminal=false refresh=true"
echo "복원 미리보기 | shell=$0 param1=act param2=preview terminal=false refresh=true"
echo "모든 claude 재시작… | shell=$0 param1=act param2=restart terminal=false refresh=true"

if [ -f "${STATE_DIR}/last.log" ]; then
  echo "---"
  echo "마지막 결과"
  # SwiftBar 는 | 를 속성 구분자로 쓰므로 바꿔 둔다
  sed 's/|/¦/g; s/^/--/; s/$/ | font=Menlo size=11/' "${STATE_DIR}/last.log"
fi

echo "---"
echo "새로고침 | refresh=true"
