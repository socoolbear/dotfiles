#!/usr/bin/env bash
#
# 예약 작업이 함께 쓰는 메일 보내기 — 주 1회 장비 점검 (machine-check-scheduled.sh) 과 매일 자동 갱신 (dotfiles-auto-update.sh) 이 부른다.
#
# claude -p (모델 haiku, 도구는 Gmail 보내기 하나만 허용) 가 claude.ai 의 Gmail 커넥터로 보낸다.
# 받는 주소는 git config user.email 이고, 명령 줄 · 로그 · 저장소에 적지 않는다 (프롬프트는 표준 입력으로 넘긴다).
# 성공은 모델의 답이 아니라 보내기 도구가 돌려준 메시지 id 로 판정한다. 본문은 부르는 쪽이 만든 고정 문구만 넣는다.
#
# 사용: send-mail.sh <제목>   (본문은 표준 입력)
#   보냈으면 exit 0, 못 보냈으면 이유 한 줄을 출력하고 exit 1. 실패 표시 파일 (다음 machine.sh 의 WARN) 은 부르는 쪽이 남긴다.
#
# launchd 의 짧은 PATH 로 불려도 claude · jq 를 찾도록 부르는 쪽이 PATH 를 채워 둔다.
# 실패 경로 시험: SEND_MAIL_CLAUDE 에 가짜 claude (또는 없는 명령 이름) 를 넣는다.

set -euo pipefail

readonly MAIL_TOOL="mcp__claude_ai_Gmail__send_message"
readonly MAIL_TIMEOUT_SECONDS=180
readonly CLAUDE_BIN="${SEND_MAIL_CLAUDE:-claude}"

# 인자: 초, 명령... — timeout 이 없는 장비는 perl alarm 으로, 그것도 없으면 제한 없이 돌린다
runLimited() {
    local seconds=$1
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "${seconds}" "$@"
    elif command -v perl >/dev/null 2>&1; then
        perl -e 'alarm shift; exec @ARGV' "${seconds}" "$@"
    else
        "$@"
    fi
}

# 인자: stream-json 출력 파일. 보내기 도구가 오류 없이 돌려준 결과의 메시지 id 를 출력한다
findSentMessageId() {
    jq -rs --arg tool "${MAIL_TOOL}" '
        [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == $tool) | .id] as $ids
        | .[] | select(.type == "user") | .message.content[]?
        | select(.type == "tool_result" and .is_error != true and (.tool_use_id as $id | $ids | index($id)))
        | (if (.content | type) == "string" then .content else ([.content[]? | .text? // empty] | join("")) end)
        | (fromjson? | .id? // empty)
    ' "$1" 2>/dev/null | head -n 1
}

# 인자: 쓸 설정 파일. ~/.claude.json 의 로컬 MCP 서버 (DB 조회 서버 등) 를 모두 막는 설정을 적는다 — 읽지 못하면 빈 설정
# 메일에 쓰지 않는 서버를 띄우지 않으려는 것이다 (비밀값 읽기 · 1Password 승인 창 · 운영 조회 서버 연결).
# --strict-mcp-config 는 claude.ai Gmail 커넥터까지 빼서 쓰지 않는다. 차단 목록은 명령 배열 전체가 같아야 걸리므로 설정에서 그대로 옮긴다
writeMcpDenySettings() {
    jq '{deniedMcpServers: [.mcpServers // {} | .[] | if .command then {serverCommand: ([.command] + (.args // []))} elif .url then {serverUrl: .url} else empty end]}' \
        "${HOME}/.claude.json" >"$1" 2>/dev/null || echo '{}' >"$1"
}

# 인자: 제목, 본문. 보냈으면 0, 못 보냈으면 이유를 출력하고 1
sendMail() {
    local subject=$1
    local body=$2
    local recipient

    # --global 만 주면 include 를 따라가지 않는다 (user.email 이 ~/.gitconfig_local 처럼 include 된 파일에 있는 장비)
    recipient=$(git config --global --includes --get user.email 2>/dev/null || true)
    [[ -n "${recipient}" ]] || { echo "받는 주소 없음 (git config user.email)"; return 1; }
    command -v "${CLAUDE_BIN}" >/dev/null 2>&1 || { echo "claude 명령 없음"; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq 명령 없음"; return 1; }

    local workDir
    workDir=$(mktemp -d) || { echo "임시 폴더를 만들지 못함 (mktemp)"; return 1; }

    writeMcpDenySettings "${workDir}/settings.json"

    local prompt
    prompt=$(printf '%s\n' \
        "ToolSearch 로 select:${MAIL_TOOL} 를 불러온 뒤, 그 도구로 아래 메일을 한 통 보내라." \
        "제목과 본문은 한 글자도 바꾸지 말고 그대로 쓴다 (본문은 평문). 다른 일은 하지 않고, 실패해도 다시 보내지 않는다." \
        "to: ${recipient}" \
        "subject: ${subject}" \
        "body:" \
        "${body}" \
        "" \
        "끝나면 SENT 또는 FAIL 한 단어만 답한다.")

    local exitCode=0
    (cd "${workDir}" && printf '%s\n' "${prompt}" | runLimited "${MAIL_TIMEOUT_SECONDS}" "${CLAUDE_BIN}" -p \
        --model haiku \
        --tools ToolSearch \
        --permission-mode dontAsk \
        --allowedTools "ToolSearch,${MAIL_TOOL}" \
        --settings "${workDir}/settings.json" \
        --no-session-persistence \
        --max-turns 5 \
        --max-budget-usd 0.2 \
        --output-format stream-json --verbose >"${workDir}/out.jsonl" 2>/dev/null) || exitCode=$?

    local messageId resultType
    messageId=$(findSentMessageId "${workDir}/out.jsonl")
    resultType=$(jq -r 'select(.type == "result") | .subtype' "${workDir}/out.jsonl" 2>/dev/null | tail -n 1)
    rm -rf "${workDir}"

    if [[ -n "${messageId}" ]]; then
        return 0
    fi

    if (( exitCode == 124 || exitCode == 142 )); then
        echo "시간 초과 (${MAIL_TIMEOUT_SECONDS}초)"
    else
        echo "보내기 도구의 성공 결과 없음 (claude exit ${exitCode}, 결과 ${resultType:-없음} — claude 로그인 · claude.ai 의 Gmail 커넥터 확인)"
    fi

    return 1
}

main() {
    local subject=${1:?제목}
    local body
    body=$(cat)

    sendMail "${subject}" "${body}"
}

main "$@"
