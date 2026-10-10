#!/bin/bash
#
# Alfred script filter — term-session 동작 목록. 부제목에 마지막 저장 요약을 보여 준다.

export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin

status=$("${HOME}/.local/bin/term-session" status 2>/dev/null || echo "term-session 미설치 — make sync")

jq -n --arg status "${status}" '{items: [
  {uid: "save", title: "저장", subtitle: "지금 상태 저장 · 마지막: \($status)", arg: "save", match: "저장 save"},
  {uid: "save-handoff", title: "저장 (handoff 포함)", subtitle: "idle 인 claude 마다 /handoff 문서를 쓰게 한 뒤 저장 (claude 마다 시간·토큰이 듦)", arg: "save-handoff", match: "저장 save handoff"},
  {uid: "close", title: "작업 정리 (handoff 후 모두 닫기)", subtitle: "handoff → 저장 → claude·tmux 정리 → Ghostty 종료 (확인 창, handoff 를 못 하면 멈춤)", arg: "close", match: "정리 close 종료 handoff"},
  {uid: "restore", title: "복원", subtitle: "사라진 층만 되살림 — claude 는 같은 대화로 resume", arg: "restore", match: "복원 restore"},
  {uid: "restore-handoff", title: "복원 (handoff 로 새 세션)", subtitle: "claude 가 꺼져 있을 때 (정리·재부팅 뒤) 새 세션을 handoff 문서 (없으면 /catchup) 로 시작", arg: "restore-handoff", match: "복원 restore handoff catchup"},
  {uid: "preview", title: "복원 미리보기", subtitle: "아무것도 만들지 않고 할 일만 보여 줌", arg: "preview", match: "미리보기 preview dry-run"},
  {uid: "restart", title: "모든 claude 재시작", subtitle: "claude·빈 셸 pane 을 제자리에서 다시 띄움 (Claude 버전업·zsh 반영)", arg: "restart", match: "재시작 restart"}
]}'
