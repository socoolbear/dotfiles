#!/usr/bin/env bash
# Stop 훅 — 멈춤 점검. 턴이 끝날 때 마지막 답변을 보고 두 가지를 한다.
#
#   1. 글 질문 (질문 창 없이 "~할까요?"·"알려 주세요"·"원하시면" 으로 끝낸 답) 인지 판정한다.
#      질문 점검 훅 (ask-precheck.sh) 은 AskUserQuestion 만 잡아서, 글 질문은 아무것도 거치지 않았다
#      (2026-11-18 집계: 14일 동안 멈춘 2,298턴 중 792턴이 글 질문, 그 답의 40% 가 "응"·"진행해줘").
#   2. 상태 꼬리표 (**지금** / **사용자 몫** / **다음**) 가 있으면 세션별 파일로 복사한다.
#      `claude-loop board` (상황판) 가 이 파일을 읽는다. 기준은 ~/.claude/AGENTS.md 「출력 길이」.
#   3. 꼬리표의 「사용자 몫」 에 항목이 있는데 분류 표시 ([운영] 등) 가 없으면 한 번 막는다.
#      1번 판정이 꼬리표를 빼고 보자 질문이 「사용자 몫」 줄로 옮겨 갔다 (2026-11-18 사용자 지적 —
#      찾아볼 수 있는 확인 수단, 선택지 묶음, 직접 할 수 있는 QA, 제안을 사용자 몫에 적고 멈춤).
#      이 점검은 아래 동작 모드와 무관하게 막는다.
#   4. 사용자에게 그대로 나가는 질문 (막지 않고 통과시키는 글 질문 · 「사용자 몫」) 을 ask-classify.sh 에 넘겨
#      Jev 분류와 함께 기록한다. 기록만 하고 판정에는 쓰지 않는다 (2026-11-18 사용자 결정 — 맞는지 먼저 본다).
#
# 동작 모드 — ~/.local/state/claude-loop/stop-gate/mode 파일의 내용
#   (없음) · record  막지 않고 기록만 한다 (기본). 오탐률을 실제 세션에서 먼저 본다
#   block            글 질문이면 한 번 막고 「꼭 묻는 목록」 (workflow.md §7) 에 드는지 판정하게 한다
# 「사용자 몫」 점검만 기록으로 돌리기: echo record > ~/.local/state/claude-loop/stop-gate/owed-mode
# 기록: ~/.local/state/claude-loop/stop-gate/log.jsonl (턴마다 한 줄)
# 끄기: touch ~/.local/state/claude-loop/disabled (claude-loop 와 같은 스위치)
#
# set -e 를 쓰지 않는 이유: Stop 훅의 exit 2 는 턴 차단이다. 예기치 못한 실패는 전부 exit 0 으로 흡수한다.
set -uo pipefail

export LC_ALL=en_US.UTF-8

STATE_DIR="${HOME}/.local/state/claude-loop"
GATE_DIR="${STATE_DIR}/stop-gate"
BOARD_DIR="${STATE_DIR}/board"
TAIL_CHARS=260
CLASSIFY_CHARS=600
FOOTER_MAX_LINES=12
OWED_NONE='^\*\*사용자 몫\*\*[^가-힣A-Za-z0-9]*없음'
OWED_TAGS='\[(운영|복구불가|외부글|본인|구조|정책|예외)\]'   # workflow.md §7 「꼭 묻는 목록」 1~7번과 같은 순서
ASK_TAIL='할까요|될까요|드릴까요|볼까요|을까요|까요[?]|[?][[:space:]]*$|알려 ?주세요|말씀해 ?주|정해 ?주세요|골라 ?주세요|원하시면|필요하시면|괜찮으시면'

# 통과시키는 질문을 뒤에서 분류·기록한다. 훅은 기다리지 않는다 (출력을 끊어야 훅 실행기가 붙잡히지 않는다).
recordAsk() {
  [[ "${asks}" == "true" || "${owes}" == "true" ]] || return 0

  (bash "${HOME}/.claude/scripts/ask-classify.sh" record text "${session_id}" "${ask_text} ${owed}" </dev/null >/dev/null 2>&1 &)
}

[[ "${AGENT_BOT:-}" == "1" ]] && exit 0
[[ -f "${STATE_DIR}/disabled" ]] && exit 0

input=$(cat)

# 구분자로 '|' 를 쓴다: IFS 가 공백문자면 빈 필드가 뭉개져 밀린다.
IFS='|' read -r session_id stop_active agent_id perm_mode cwd < <(
  jq -r '[ .session_id // "",
           (.stop_hook_active // false | tostring),
           .agent_id // "",
           .permission_mode // "",
           .cwd // "" ] | join("|")' <<<"${input}" 2>/dev/null
) || exit 0

[[ -n "${session_id}" ]] || exit 0
[[ -z "${agent_id}" ]]   || exit 0   # 서브에이전트 · in-process 팀메이트의 종료
[[ "${perm_mode}" == "plan" ]] && exit 0

message=$(jq -r '.last_assistant_message // ""' <<<"${input}" 2>/dev/null) || exit 0

[[ -n "${message}" ]] || exit 0

# --- 1. 판정 ---
# 꼬리표의 「사용자 몫」 은 원래 부탁하는 말투라, 글 질문 판정은 꼬리표 앞의 본문 끝으로 한다
body=$(awk '/^\*\*지금\*\*/ { start = NR } { lines[NR] = $0 } END { last = (start ? start - 1 : NR); for (i = 1; i <= last; i++) print lines[i] }' <<<"${message}")
ask_text=$(tr '\n\t' '  ' <<<"${body}")
tail_text="${ask_text}"
(( ${#tail_text} > TAIL_CHARS )) && tail_text="${tail_text: -${TAIL_CHARS}}"   # 짧은 글에 음수 오프셋을 쓰면 빈 문자열이 된다
(( ${#ask_text} > CLASSIFY_CHARS )) && ask_text="${ask_text: -${CLASSIFY_CHARS}}"
footer=$(awk '/^\*\*지금\*\*/ { start = NR } { lines[NR] = $0 } END { if (start) for (i = start; i <= NR; i++) print lines[i] }' <<<"${message}")
owed=$(awk '/^\*\*사용자 몫\*\*/ { inside = 1 } /^\*\*다음\*\*/ { inside = 0 } inside' <<<"${footer}")
asks=false
has_footer=false
owes=false
tagged=false

[[ "${tail_text}" =~ ${ASK_TAIL} ]] && asks=true
grep -q '^\*\*지금\*\*' <<<"${message}" && grep -q '^\*\*다음\*\*' <<<"${message}" && has_footer=true
[[ -n "${owed}" ]] && ! grep -qE "${OWED_NONE}" <<<"${owed}" && owes=true
grep -qE "${OWED_TAGS}" <<<"${owed}" && tagged=true

# --- 2. 꼬리표를 상황판 파일로 복사 (마지막 **지금** 줄부터 끝까지) ---
if [[ "${has_footer}" == "true" ]]; then
  mkdir -p "${BOARD_DIR}" && head -n "${FOOTER_MAX_LINES}" <<<"${footer}" >"${BOARD_DIR}/${session_id}.md"
fi

# --- 3. 기록 ---
mkdir -p "${GATE_DIR}" \
  && jq -nc --arg at "$(date '+%FT%T')" --arg session "${session_id}" --arg cwd "${cwd}" --arg tail "${tail_text}" \
       --argjson asks "${asks}" --argjson footer "${has_footer}" --argjson reentry "${stop_active}" \
       --argjson owes "${owes}" --argjson tagged "${tagged}" --arg owed "${owed}" \
       '{at: $at, session: $session, cwd: $cwd, asks: $asks, footer: $footer, owes: $owes, tagged: $tagged, reentry: $reentry, tail: $tail}
        + (if $owes then {owed: $owed} else {} end)' \
       >>"${GATE_DIR}/log.jsonl" 2>/dev/null

# --- 4. 차단 ---
if [[ "${stop_active}" == "true" ]]; then   # 재진입 — 한 번 막은 뒤에는 통과시킨다 (무한 차단 방지)
  recordAsk
  exit 0
fi

owed_mode=$(cat "${GATE_DIR}/owed-mode" 2>/dev/null || echo block)

if [[ "${owes}" == "true" && "${tagged}" == "false" && "${owed_mode}" != "record" ]]; then
  jq -n '{
    decision: "block",
    reason: "[사용자 몫 점검] 꼬리표의 「사용자 몫」 에 분류 표시 없는 항목이 있다. 「사용자 몫」 도 질문이다. 항목마다 아래 순서로 걸러낸 뒤 다시 끝내라 (기준: ~/.claude/docs/workflow.md §7 「사용자 몫에 적기 전에」).\n1. QA·확인을 사용자에게 넘겼는가 (\"한 번 써 보기\" · \"화면 확인\")? → 지금 직접 한다 (aside 브라우저 · 실제 호출 · 로그). 수단이 없거나 보안·고위험 동작일 때만 남긴다\n2. 찾아볼 수 있는 사실·수단인가 (\"~가 있는지\" · \"어떻게 확인할지\")? → 코드·DB·로그·관리 화면·문서를 지금 직접 찾는다. 못 찾았을 때만 찾아본 곳을 적고 남긴다\n3. 선택지나 제안을 통째로 넘겼는가 (\"그대로 둘지, 고칠지, 되돌릴지\" · \"~도 맞출지 결정\")? → 추천안을 스스로 고르고, 꼭 묻는 목록에 닿기 직전까지 지금 진행한다 (후속 PR 올리기 · 초안 쓰기까지). 목록에 닿는 마지막 동작 하나만 남긴다. 요청 범위를 넘는 제안은 notes.md 「질문 대기열」 에 적고 사용자 몫에는 쓰지 않는다\n4. 꼭 묻는 목록에 드는가? → 들지 않으면 추천안대로 지금 진행하고 진행 문서 「결정 로그」 에 [위임] 으로 남긴다\n5. 「다음」 에 사용자 답 없이 할 수 있는 일이 있는가 (초안 작성 · 조사 · 검증)? → 그 일을 먼저 끝낸다\n남은 항목만 `[분류] 승인·결정할 것 하나 — 추천안` 으로 적는다. 분류는 [운영] [복구불가] [외부글] [본인] [구조] [정책] [예외] 중 하나다. 남은 것이 없으면 `없음` 으로 쓴다."
  }'
  exit 0
fi

mode=$(cat "${GATE_DIR}/mode" 2>/dev/null || echo record)

if [[ "${mode}" != "block" || "${asks}" != "true" ]]; then
  recordAsk
  exit 0
fi

jq -n '{
  decision: "block",
  reason: "[멈춤 점검] 답변이 묻는 말로 끝났다. 아래로 판정한 뒤 다시 끝내라 (기준: ~/.claude/docs/workflow.md §7 「꼭 묻는 목록」).\n1. 꼭 묻는 목록 (운영에 닿는 동작 / 되돌릴 수 없는 것 / 사용자 이름으로 남에게 나가는 글 / 사용자의 몸이 있어야 하는 일 / 구조적 결정 / 선례가 없거나 충돌하는 제품·정책·범위 결정 / 한도·예외·보안 경계) 에 드는가?\n   → 들지 않으면 묻지 말고 추천안대로 지금 진행하고, 진행 문서 「결정 로그」 에 [위임] 으로 남긴다\n2. 요청 범위를 넘는 제안인가? → 스스로 진행하지 않고 notes.md 「질문 대기열」 에 추천안과 함께 적은 뒤 원래 일을 계속한다\n3. 목록에 들고, 답 없이는 더 할 일이 없는가? → 추천안을 붙여 다시 끝낸다 (두 번째는 통과한다). 다른 할 일이 남았으면 대기열에 적고 그 일을 먼저 한다\n끝낼 때는 답 끝에 상태 꼬리표 (**지금** / **사용자 몫** / **다음**) 를 붙인다."
}'
