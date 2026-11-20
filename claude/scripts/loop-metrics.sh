#!/usr/bin/env bash
# 사람 개입 지표 — 최근 N 일 (기본 1) 메인 세션 transcript 에서 질문·입력·중단 수를 센다.
# claude-loop brief 가 아침 요약에 싣는다. 결정 개입 줄이기 (workflow.md §7) 의 효과를 보는 용도.
#
#   loop-metrics.sh [days]
#
# 세는 것
#   - 질문 창: AskUserQuestion 의 질문 수 / 그중 실행 승인 (커밋·머지·push·PR·배포) 헤더 / 같은 헤더 반복
#   - 글 질문: 질문 창 없이 답변 끝을 "~할까요?"·"알려 주세요"·"원하시면" 으로 끝낸 뒤 사람이 입력한 턴
#     (정규식 판정이라 오차가 있다 — 추세를 보는 용도)
#   - 사람 입력: 문자열 user 메시지 중 태그 (<teammate-message> · <task-notification> 등) · 야간 루프 메시지 · compact 요약을 뺀 것
#     (다른 세션이 보낸 일반 문장 메시지는 구분하지 못해 함께 세진다)
#     - 승인: "응"·"네" 로 시작하는 40자 미만 입력 / 상태 묻기: "진행 상황 알려줘"·"이제 뭐하면 돼" 류 60자 미만 입력
#   - 중단: "Request interrupted by user"
set -euo pipefail

readonly DAYS="${1:-1}"
readonly PROJECTS_DIR="${HOME}/.claude/projects"
readonly ASK_TAIL='할까요|될까요|드릴까요|볼까요|을까요|까요[?]|[?][[:space:]]*$|알려 ?주세요|말씀해 ?주|정해 ?주세요|골라 ?주세요|원하시면|필요하시면|괜찮으시면'
readonly STATUS_ASK='진행 ?상황|이제 뭐|다음에? ?(뭐|할 ?일)|뭐 ?하면 ?(돼|되)|더 진행 ?할|남은 작업|어디까지'
readonly APPROVAL='^(응|ㅇㅇ|네|넵|그래|좋아|오케이|ok|ㅇㅋ|맞아)([ ,.!]|$)'

transcripts=$(find "${PROJECTS_DIR}" -name '*.jsonl' -mtime "-${DAYS}" -not -path '*/subagents/*' 2>/dev/null || true)

if [[ -z "${transcripts}" ]]; then
  echo "최근 ${DAYS}일 transcript 없음"
  exit 0
fi

# 오래 열린 세션 파일에는 옛 기록도 들어 있어 파일 수정 시각이 아니라 줄마다의 timestamp 로 기간을 자른다.
# 한 번만 훑어 사건 줄로 바꾼다: 종류<TAB>세션<TAB>글 (줄바꿈은 공백으로 — 여러 줄 입력이 여러 건으로 세지지 않게)
#   q 질문 창 헤더 / a 어시스턴트 글의 끝 260자 / h 사람 입력의 앞 80자 / i 중단
since=$(date -u -v-"${DAYS}"d '+%Y-%m-%dT%H:%M:%S')
events=$(tr '\n' '\0' <<<"${transcripts}" | xargs -0 cat 2>/dev/null | jq -r --arg since "${since}" '
  def flat: gsub("[\\n\\t\\r]+"; " ") | sub("^ +"; "");
  select((.timestamp // "") >= $since and (.isSidechain | not) and (.isMeta | not))
  | (.sessionId // "") as $session
  | if .type == "assistant" then
      (.message.content // [])[]?
      | if .type == "tool_use" and .name == "AskUserQuestion" then .input.questions[]? | "q\t\($session)\t\(.header // "" | flat)"
        elif .type == "text" and (.text | length) > 0 then "a\t\($session)\t\(.text | .[-260:] | flat)"
        else empty end
    elif .type == "user" and ((.message.content | type) == "string") then
      (.message.content | flat) as $text
      | if ($text | startswith("[Request interrupted")) then "i\t\($session)\t"
        elif ($text | test("^(<|\\[야간 루프|Caveat|This session is being continued)")) then empty
        else "h\t\($session)\t\($text | .[0:80])" end
    elif .type == "user" then
      (.message.content // [])[]? | select(.type == "text" and (.text | startswith("[Request interrupted"))) | "i\t\($session)\t"
    else empty end' 2>/dev/null || true)

headers=$(awk -F'\t' '$1 == "q" { print $3 }' <<<"${events}")
questions=$(grep -c . <<<"${headers}" || true)
execution=$(grep -cE '커밋|머지|병합|push|PR|배포|commit|merge' <<<"${headers}" || true)
repeated=$(grep . <<<"${headers}" | sort | uniq -d | wc -l | tr -d ' ')
sessions=$(grep -c . <<<"${transcripts}")

# 사람 입력마다 그 세션의 직전 어시스턴트 글이 묻는 말투로 끝났는지 본다
read -r humanInputs textAsks approvals statusAsks interrupts < <(
  LC_ALL=en_US.UTF-8 awk -F'\t' -v askTail="${ASK_TAIL}" -v statusAsk="${STATUS_ASK}" -v approval="${APPROVAL}" '
    $1 == "a" { lastText[$2] = $3; next }
    $1 == "i" { interrupts++; next }
    $1 == "h" {
      humans++
      if (lastText[$2] ~ askTail) textAsks++
      if (length($3) < 40 && tolower($3) ~ approval) approvals++
      else if (length($3) < 60 && $3 ~ statusAsk) statusAsks++
      delete lastText[$2]
    }
    END { print humans + 0, textAsks + 0, approvals + 0, statusAsks + 0, interrupts + 0 }' <<<"${events}"
)

cat <<EOF
최근 ${DAYS}일 (세션 ${sessions}개)
- 질문 창 ${questions}건 (실행 승인 헤더 ${execution}건, 반복 헤더 ${repeated}종)
- 글 질문 ${textAsks}건 (답변 끝을 묻는 말로 끝낸 턴)
- 사람 입력 ${humanInputs}건 (승인 ${approvals}건, 상태 묻기 ${statusAsks}건), 중단 ${interrupts}건
EOF
