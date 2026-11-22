#!/usr/bin/env bash
#
# 이 장비의 상태 점검 (dotfiles-doctor 의 machine.sh) 을 주 1회 돌리는 예약 작업 (launchd: com.socoolbear.dotfiles-machine-check).
#
# 점검 출력은 로그에 남기고, FAIL 또는 WARN 이 1건 이상일 때만 메일 한 통을 보낸다 (macOS 알림은 띄우지 않는다 — 2026-11-21 사용자 결정).
# 메일은 자동 갱신과 함께 쓰는 scripts/send-mail.sh (claude -p + claude.ai 의 Gmail 커넥터) 로 보낸다.
# 받는 주소는 git config user.email 이고, 로그 · 저장소에 적지 않는다.
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

markMailFailed() {
    local reason=$1

    mkdir -p "$(dirname "${MAIL_FAILED_FLAG}")"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "${reason}" >"${MAIL_FAILED_FLAG}"
    log "메일: 실패 (${reason})"
}

# 인자: 저장소, 제목, 본문. 자동 갱신과 함께 쓰는 scripts/send-mail.sh 로 보낸다. 못 보냈으면 이유를 출력하고 1
sendMail() {
    SEND_MAIL_CLAUDE="${CLAUDE_BIN}" bash "$1/scripts/send-mail.sh" "$2" <<<"$3"
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

# 인자: 저장소, 점검 출력. FAIL · WARN 이 1건 이상이면 메일을 보내고 결과를 로그 · 실패 표시 파일에 남긴다
mailResult() {
    local dotfiles=$1
    local output=$2
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
    if reason=$(sendMail "${dotfiles}" "${subject}" "${body}"); then
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

    local dotfiles
    dotfiles=$(findDotfiles)

    if [[ "${1:-}" == "--test-mail" ]]; then
        local reason
        if reason=$(sendMail "${dotfiles}" "dotfiles 장비 점검 (시험) — $(machineName)" "시험 메일입니다 — 실제 점검 결과가 아닙니다. 자세한 내용은 make machine-check-log"); then
            log "메일 시험: 보냄"
            echo "시험 메일을 보냈습니다 (점검은 돌리지 않음, 실패 표시 파일은 건드리지 않음)."
        else
            log "메일 시험: 실패 (${reason})"
            echo "시험 메일을 보내지 못했습니다: ${reason}"
        fi
        return 0
    fi

    rotateLog

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
    mailResult "${dotfiles}" "${output}"
    log "===== 완료 ====="
}

main "$@"
