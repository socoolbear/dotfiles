#!/usr/bin/env bash
#
# 이 장비의 상태 점검 (dotfiles-doctor 의 machine.sh) 을 주 1회 돌리는 예약 작업 (launchd: com.socoolbear.dotfiles-machine-check).
#
# 점검 출력은 로그에 남기고, FAIL 또는 WARN 이 1건 이상일 때만 메일 한 통을 보낸다 (macOS 알림은 띄우지 않는다 — 2026-11-21 사용자 결정).
# 메일은 claude -p 가 claude.ai 의 Gmail 커넥터로 보낸다. 받는 주소는 git config user.email 이고, 로그 · 저장소에 적지 않는다.
# 점검 항목 줄에는 서버 이름 · 경로가 섞일 수 있어 메일에는 건수와 항목이 나온 영역 제목 (machine.sh 의 고정 문구) 만 넣는다.
#
# 발송에 실패하면 다른 알림 없이 로그에 남기고 실패 표시 파일을 둔다. 다음 machine.sh 가 그 파일을 WARN 으로 내고,
# 세션 시작 때의 doctor 제안 (suggest.sh) 도 그 파일을 본다. 다음 발송이 성공하면 파일을 지운다.
#
# launchd 는 PATH 가 /usr/bin:/bin:/usr/sbin:/sbin 뿐이라 Homebrew · mise 의 명령 (claude · gh · npm · node · jq) 을 못 찾는다.
# 그래서 여기서 PATH 를 채운다. 그래도 없는 명령은 machine.sh 가 WARN 으로 낸다.
#
# 즉시 실행: dotfiles-machine-check (make machine-check)
# 메일만 시험: dotfiles-machine-check --test-mail

set -euo pipefail

readonly LOG="${HOME}/Library/Logs/dotfiles-machine-check.log"
readonly MAX_LOG_BYTES=$((1024 * 1024))
readonly MAIL_FAILED_FLAG="${HOME}/.local/state/dotfiles-machine-check/mail-failed"
readonly MAIL_TOOL="mcp__claude_ai_Gmail__send_message"
readonly MAIL_TIMEOUT_SECONDS=180
readonly CLAUDE_BIN="${MACHINE_CHECK_CLAUDE:-claude}"   # 실패 경로 시험용으로 바꿀 수 있다

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"${LOG}"
}

rotateLog() {
    [[ -f "${LOG}" ]] || return 0

    local size
    size=$(stat -f%z "${LOG}")

    if (( size > MAX_LOG_BYTES )); then
        mv -f "${LOG}" "${LOG}.1"
    fi
}

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

# 인자: stream-json 출력 파일. 보내기 도구가 오류 없이 돌려준 결과의 메시지 id 를 출력한다 (모델의 답이 아니라 도구 결과로 판정)
findSentMessageId() {
    jq -rs --arg tool "${MAIL_TOOL}" '
        [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == $tool) | .id] as $ids
        | .[] | select(.type == "user") | .message.content[]?
        | select(.type == "tool_result" and .is_error != true and (.tool_use_id as $id | $ids | index($id)))
        | (if (.content | type) == "string" then .content else ([.content[]? | .text? // empty] | join("")) end)
        | (fromjson? | .id? // empty)
    ' "$1" 2>/dev/null | head -n 1
}

markMailFailed() {
    local reason=$1

    mkdir -p "$(dirname "${MAIL_FAILED_FLAG}")"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "${reason}" >"${MAIL_FAILED_FLAG}"
    log "메일: 실패 (${reason})"
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
    workDir=$(mktemp -d)

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

# 인자: 점검 출력. FAIL · WARN 이 나온 영역 제목 (machine.sh 의 '## ' 줄 — 고정 문구) 을 쉼표로 잇는다
listProblemAreas() {
    awk '
        /^## / { area = substr($0, 4); next }
        /^\[(FAIL|WARN)\]/ && area != "" && !(area in seen) { seen[area] = 1; areas = areas (areas == "" ? "" : ", ") area }
        END { print areas }
    ' <<<"$1"
}

machineName() {
    scutil --get LocalHostName 2>/dev/null || hostname -s
}

# 인자: 점검 출력. FAIL · WARN 이 1건 이상이면 메일을 보내고 결과를 로그 · 실패 표시 파일에 남긴다
mailResult() {
    local output=$1
    local failCount warnCount
    failCount=$(grep -c '^\[FAIL\]' <<<"${output}" || true)
    warnCount=$(grep -c '^\[WARN\]' <<<"${output}" || true)

    if (( failCount + warnCount == 0 )); then
        log "메일: 보내지 않음 (FAIL · WARN 없음)"
        return 0
    fi

    local machine subject body
    machine=$(machineName)
    subject="dotfiles 장비 점검: FAIL ${failCount} · WARN ${warnCount} (${machine})"
    body=$(printf '%s\n' \
        "${machine} 의 주 1회 장비 점검 결과입니다 ($(date '+%Y-%m-%d %H:%M'))." \
        "FAIL ${failCount}건 · WARN ${warnCount}건" \
        "항목이 나온 영역: $(listProblemAreas "${output}")" \
        "" \
        "자세한 내용: make machine-check-log" \
        "고치기: Claude Code 에서 \"dotfiles 점검해줘\" (dotfiles-doctor)")

    local reason
    if reason=$(sendMail "${subject}" "${body}"); then
        rm -f "${MAIL_FAILED_FLAG}"
        log "메일: 보냄"
    else
        markMailFailed "${reason}"
    fi
}

# ~/.local/bin 의 링크를 따라가 저장소 위치를 찾는다 (dotfiles 를 ~/.dotfiles 밖에 둔 장비도 맞게)
findDotfiles() {
    local scriptPath="${BASH_SOURCE[0]}"

    if [[ -L "${scriptPath}" ]]; then
        scriptPath=$(readlink "${scriptPath}")
    fi

    (cd "$(dirname "${scriptPath}")/.." && pwd)
}

main() {
    mkdir -p "$(dirname "${LOG}")"
    export PATH="${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:${PATH}"

    if [[ "${1:-}" == "--test-mail" ]]; then
        local reason
        if reason=$(sendMail "dotfiles 장비 점검 (시험) — $(machineName)" "시험 메일입니다 — 실제 점검 결과가 아닙니다. 자세한 내용은 make machine-check-log"); then
            log "메일 시험: 보냄"
            echo "시험 메일을 보냈습니다 (점검은 돌리지 않음, 실패 표시 파일은 건드리지 않음)."
        else
            log "메일 시험: 실패 (${reason})"
            echo "시험 메일을 보내지 못했습니다: ${reason}"
        fi
        return 0
    fi

    rotateLog

    local dotfiles
    dotfiles=$(findDotfiles)
    local machineScript="${dotfiles}/.claude/skills/dotfiles-doctor/scripts/machine.sh"

    if [[ ! -f "${machineScript}" ]]; then
        log "!!! 점검 스크립트 없음: ${machineScript} — 중단"
        markMailFailed "점검 스크립트를 찾지 못함"
        return 0
    fi

    # 점검이 끝날 때까지 맥이 잠들지 않게 한다 (깨어난 직후 실행되면 곧 다시 잠들 수 있다)
    /usr/bin/caffeinate -i -w $$ &

    log "===== 시작 ====="

    local output
    output=$(DOTFILES="${dotfiles}" bash "${machineScript}" 2>&1) || true
    printf '%s\n' "${output}" >>"${LOG}"

    local failCount warnCount
    failCount=$(grep -c '^\[FAIL\]' <<<"${output}" || true)
    warnCount=$(grep -c '^\[WARN\]' <<<"${output}" || true)

    log "결과: FAIL ${failCount}건 · WARN ${warnCount}건"
    mailResult "${output}"
    log "===== 완료 ====="
}

main "$@"
