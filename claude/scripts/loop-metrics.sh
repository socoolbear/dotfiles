#!/usr/bin/env bash
# 사람 개입 지표 — 최근 N 일 (기본 1) 메인 세션 transcript 에서 질문·입력·중단 수를 센다.
# claude-loop brief 가 아침 요약에 싣는다. 결정 개입 줄이기 (workflow.md §7) 의 효과를 보는 용도.
#
#   loop-metrics.sh [days]
#
# 세는 것
#   - 질문: AskUserQuestion 의 질문 수 / 그중 실행 승인 (커밋·머지·push·PR·배포) 헤더 / 같은 헤더 반복
#   - 사람 입력: 문자열 user 메시지 중 태그 (<teammate-message> · <task-notification> 등) 와 야간 루프 메시지를 뺀 것
#     (다른 세션이 보낸 일반 문장 메시지는 구분하지 못해 함께 세진다)
#   - 중단: "Request interrupted by user"
set -euo pipefail

readonly DAYS="${1:-1}"
readonly PROJECTS_DIR="${HOME}/.claude/projects"

transcripts=$(find "${PROJECTS_DIR}" -name '*.jsonl' -mtime "-${DAYS}" -not -path '*/subagents/*' 2>/dev/null || true)

if [[ -z "${transcripts}" ]]; then
  echo "최근 ${DAYS}일 transcript 없음"
  exit 0
fi

# 오래 열린 세션 파일에는 옛 기록도 들어 있어 파일 수정 시각이 아니라 줄마다의 timestamp 로 기간을 자른다
since=$(date -u -v-"${DAYS}"d '+%Y-%m-%dT%H:%M:%S')
entries=$(tr '\n' '\0' <<<"${transcripts}" | xargs -0 cat 2>/dev/null \
  | jq -c --arg since "${since}" 'select((.timestamp // "") >= $since)' 2>/dev/null || true)

headers=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="AskUserQuestion") | .input.questions[]? | .header // ""' <<<"${entries}" 2>/dev/null || true)

human_inputs=$(jq -r 'select(.type=="user" and (.isMeta|not) and ((.message.content|type)=="string")) | .message.content | .[0:20]' <<<"${entries}" 2>/dev/null \
  | grep -cvE '^(<|\[Request interrupted|\[야간 루프|Caveat)' || true)

interrupts=$(grep -o 'Request interrupted by user' <<<"${entries}" | wc -l | tr -d ' ')

questions=$(grep -c . <<<"${headers}" || true)
execution=$(grep -cE '커밋|머지|병합|push|PR|배포|commit|merge' <<<"${headers}" || true)
repeated=$(grep . <<<"${headers}" | sort | uniq -d | wc -l | tr -d ' ')
sessions=$(grep -c . <<<"${transcripts}")

cat <<EOF
최근 ${DAYS}일 (세션 ${sessions}개)
- 질문 ${questions}건 (실행 승인 헤더 ${execution}건, 반복 헤더 ${repeated}종)
- 사람 입력 ${human_inputs}건, 중단 ${interrupts}건
EOF
