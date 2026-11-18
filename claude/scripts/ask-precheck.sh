#!/usr/bin/env bash
# AskUserQuestion PreToolUse 훅 — 사용자에게 묻기 직전에 "정말 물어야 하는가" 를 점검하게 한다.
# 근거: 대형 태스크 하나의 14일 질문 229건 중 실행 승인 37건 · 선례로 답이 나오는 기술 선택 93건 · 반복 약 19건 (2026-11-17 분석).
# 기준은 ~/.dotfiles/claude/docs/workflow.md §7.
#
#   - 낮: 세션의 첫 질문만 1회 차단하고 점검 목록을 보여준다. 걸러낸 뒤 다시 부르면 통과
#   - 야간 모드 (claude-loop 가 일을 맡긴 세션): 매번 차단 — 밤에는 묻지 않고 질문 대기열에 남긴다
#   - AGENT_BOT=1 (Slack 봇 세션): 건너뛴다
set -uo pipefail

NIGHT_DIR="${HOME}/.local/state/claude-loop/night"
STATE_DIR="${TMPDIR:-/tmp}/claude-ask-precheck"

[[ "${AGENT_BOT:-}" == "1" ]] && exit 0

input=$(cat)
session_id=$(jq -r '.session_id // empty' <<<"${input}" 2>/dev/null) || exit 0

[[ -n "${session_id}" ]] || exit 0

if [[ -f "${NIGHT_DIR}/${session_id}" ]] \
  || [[ "${CLAUDE_NIGHT:-}" == "1" && -f "${NIGHT_DIR}/active" && ! -f "${NIGHT_DIR}/released/${session_id}" ]]; then
  cat >&2 <<'EOF'
[야간 질문 금지] 밤에는 사용자에게 묻지 않는다.
- 태스크 notes.md 의 「질문 대기열」 에 질문 / 추천안 / 근거 / 상태(대기) 로 남기고, 그 질문과 무관한 일을 계속한다
- 더 할 일이 없으면 진행 문서의 「야간 결과」 에 멈춘 이유를 적고 끝낸다
EOF
  exit 2
fi

state_file="${STATE_DIR}/${session_id}"

[[ -f "${state_file}" ]] && exit 0

mkdir -p "${STATE_DIR}" && touch "${state_file}"

cat >&2 <<'EOF'
[질문 전 점검] 이 세션의 첫 질문이다. 아래로 걸러낸 뒤 남은 것만 다시 물어라 (기준: ~/.claude/docs/workflow.md §7 「꼭 묻는 목록」).
1. 꼭 묻는 목록에 드는가? — 운영에 닿는 동작 / 되돌릴 수 없는 것 (삭제·force push·돈 이동) / 사용자 이름으로 남에게 나가는 글 (초안 작성은 제외) / 사용자의 몸이 있어야 하는 일 (1Password 잠금 해제·휴대폰 승인·CAPTCHA — 로그인·OTP 는 aside 의 1Password 확장으로 직접 한다) / 구조적 결정 / 선례가 없거나 충돌하는 제품·정책·범위 결정 / 한도·예외·보안 경계
   → 들지 않으면 묻지 않는다. 추천안대로 진행하고 진행 문서 「결정 로그」 에 [위임] 으로 남긴다 (커밋·push·PR·dev 배포·조사 이어가기·초안 만들기·Jira 상태가 여기 든다)
2. 선례·결정 로그·DECISIONS·notes 에 답이 있는가? 그 파일들을 grep 했는가? → 있으면 따르고 근거를 한 줄 남긴다
3. 목록에는 없지만 범위가 늘거나 되돌리는 데 반나절 넘게 드는 제안인가? → 서브에이전트 1명의 반박 검토를 승인으로 삼아 진행한다 ([위임·검토])
4. 지금 답이 없어도 다른 일을 할 수 있는가? → notes.md 「질문 대기열」 에 추천안과 함께 남기고 계속 진행한다
5. 같은 주제를 여러 질문으로 나눠 묻고 있지 않은가? → 한 번에 묶는다
EOF
exit 2
