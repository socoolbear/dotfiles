#!/usr/bin/env bash
#
# 이 장비의 상태 점검 (dotfiles-doctor 의 machine.sh) 을 주 1회 돌리는 예약 작업 (launchd: com.socoolbear.dotfiles-machine-check).
#
# 점검 출력은 로그에 남기고, FAIL 또는 WARN 이 1건 이상이면 macOS 알림을 띄운다 (가장 심한 항목 한 줄 + 건수, 누르면 로그).
# machine.sh 는 비밀값을 출력하지 않으므로 로그 · 알림에도 비밀값이 남지 않는다.
#
# launchd 는 PATH 가 /usr/bin:/bin:/usr/sbin:/sbin 뿐이라 Homebrew · mise 의 명령 (gh · npm · node) 을 못 찾는다.
# 그래서 여기서 PATH 를 채운다. 그래도 없는 명령은 machine.sh 가 WARN 으로 낸다.
#
# 즉시 실행: dotfiles-machine-check (make machine-check)
# 알림만 시험: dotfiles-machine-check --test-notify

set -euo pipefail

readonly LOG="${HOME}/Library/Logs/dotfiles-machine-check.log"
readonly MAX_LOG_BYTES=$((1024 * 1024))
readonly NOTIFY_TITLE="dotfiles 장비 점검"
readonly NOTIFY_GROUP="dotfiles-machine-check"

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

findNotifier() {
    local candidate

    for candidate in /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier; do
        if [[ -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

# 인자: 제목, 본문. terminal-notifier (Brewfile) 로 띄우면 누르면 로그가 열리고, 같은 그룹의 이전 알림을 바꿔 쌓이지 않는다.
# terminal-notifier 는 시스템 설정 > 알림 에서 허용돼 있어야 한다 — 허용되지 않았으면 exit 3 으로 끝난다 (2026-11-21 이 장비).
# 그때와 terminal-notifier 가 없을 때는 osascript 로 띄운다. 이 알림은 누르면 스크립트 편집기가 열리므로 로그 명령을 본문에 적는다.
notify() {
    local title=$1
    local message=$2
    local notifier

    if notifier=$(findNotifier) \
        && "${notifier}" -title "${title}" -message "${message} — 누르면 로그" -group "${NOTIFY_GROUP}" -open "file://${LOG}" >/dev/null 2>&1; then
        log "알림: terminal-notifier"
        return 0
    fi

    log "알림: osascript (terminal-notifier 없음 또는 알림 허용 안 됨)"
    /usr/bin/osascript - "${message} — make machine-check-log 로 확인" "${title}" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
    display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
}

# 인자: 점검 출력, 제목. FAIL · WARN 이 있으면 가장 심한 항목 하나의 내용과 건수를 알린다 (machine.sh 출력에는 비밀값이 없다)
notifyResult() {
    local output=$1
    local title=$2
    local failCount warnCount headline

    failCount=$(grep -c '^\[FAIL\]' <<<"${output}" || true)
    warnCount=$(grep -c '^\[WARN\]' <<<"${output}" || true)
    (( failCount + warnCount > 0 )) || return 0

    headline=$( { grep -m1 '^\[FAIL\]' <<<"${output}" || grep -m1 '^\[WARN\]' <<<"${output}"; } | sed -E 's/^\[[A-Z]+\] //')
    notify "${title}" "${headline} (FAIL ${failCount} · WARN ${warnCount}, 고치기는 dotfiles-doctor)"
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
    if [[ "${1:-}" == "--test-notify" ]]; then
        mkdir -p "$(dirname "${LOG}")"
        notify "${NOTIFY_TITLE} (시험)" "시험 알림 — 실제 점검 결과가 아님"
        echo "시험 알림을 한 번 띄웠습니다 (점검은 돌리지 않음). 경로: $(tail -n 1 "${LOG}")"
        return 0
    fi

    mkdir -p "$(dirname "${LOG}")"
    rotateLog

    local dotfiles
    dotfiles=$(findDotfiles)
    local machineScript="${dotfiles}/.claude/skills/dotfiles-doctor/scripts/machine.sh"

    if [[ ! -f "${machineScript}" ]]; then
        log "!!! 점검 스크립트 없음: ${machineScript} — 중단"
        notify "${NOTIFY_TITLE}" "점검 스크립트를 찾지 못함"
        return 1
    fi

    export PATH="${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:${PATH}"

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
    notifyResult "${output}" "${NOTIFY_TITLE}"
    log "===== 완료 ====="
}

main "$@"
