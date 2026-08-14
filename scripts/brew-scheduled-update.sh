#!/usr/bin/env bash
#
# 정해진 시각에 Homebrew 를 갱신하는 예약 작업 (launchd: com.socoolbear.brew-scheduled-update).
#
# zshrc 의 HOMEBREW_NO_AUTO_UPDATE=1 로 brew 명령 실행 중 자동 갱신을 껐으므로, 갱신 책임은 이 스크립트에 있다.
#
# 예약 시각은 plist 의 StartCalendarInterval 이 정한다. 다만 launchd 는 예약 시각에 맥이 잠들어 있었으면
# 깨어난 직후 작업을 실행하므로, 실제 실행 시각이 예약 시각과 크게 어긋날 수 있다.
# 그래서 실행 허용 구간을 벗어난 지연 실행은 건너뛰고 다음 예약을 기다린다.
# 단, OVERDUE_DAYS 넘게 한 번도 실행되지 못했으면 갱신이 너무 밀리지 않도록 구간과 무관하게 1 회 실행한다.
#
# 즉시 실행: BREW_SCHEDULED_UPDATE_FORCE=1 brew-scheduled-update

set -euo pipefail

# 실행 허용 구간 — 예약 시각(04:30)을 포함하며, 이 구간을 벗어난 지연 실행은 건너뛴다
readonly RUN_WINDOW_START=3       # 03:00 이상
readonly RUN_WINDOW_END=8         # 08:00 미만

# 이 기간 넘게 실행 기록이 없으면 허용 구간을 무시하고 1 회 실행
readonly OVERDUE_DAYS=7

readonly STAMP="${HOME}/.local/state/brew-scheduled-update/last-run"
readonly LOG="${HOME}/Library/Logs/brew-scheduled-update.log"
readonly MAX_LOG_BYTES=$((1024 * 1024))

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

findBrew() {
    local candidate

    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

formatRunWindow() {
    printf '%02d:00~%02d:00' "${RUN_WINDOW_START}" "${RUN_WINDOW_END}"
}

isWithinRunWindow() {
    local hour
    hour=$(date '+%-H')

    (( hour >= RUN_WINDOW_START && hour < RUN_WINDOW_END ))
}

isOverdue() {
    [[ -n "$(find "${STAMP}" -mtime "+${OVERDUE_DAYS}" 2>/dev/null)" ]]
}

runStep() {
    local name=$1
    shift

    log "==> brew ${name}"

    if ! "$@" >>"${LOG}" 2>&1; then
        log "!!! brew ${name} 실패 — 다음 단계 계속 진행"
    fi
}

main() {
    mkdir -p "$(dirname "${STAMP}")" "$(dirname "${LOG}")"
    rotateLog

    # 설치 직후 곧바로 대규모 업그레이드가 돌지 않도록, 실행 기록만 남기고 다음 예약으로 넘긴다
    if [[ ! -f "${STAMP}" ]]; then
        touch "${STAMP}"
        log "실행 기록 없음 — 초기화만 하고 다음 예약 시각부터 갱신"
        return 0
    fi

    if [[ -z "${BREW_SCHEDULED_UPDATE_FORCE:-}" ]] && ! isWithinRunWindow && ! isOverdue; then
        log "실행 허용 구간($(formatRunWindow)) 밖의 지연 실행 — 건너뛰고 다음 예약 대기"
        return 0
    fi

    local brew
    if ! brew=$(findBrew); then
        log "!!! brew 실행 파일을 찾을 수 없음 — 중단"
        return 1
    fi

    # 아래에서 명시적으로 update 하므로 brew 자체 자동 갱신은 끈다
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1
    export HOMEBREW_NO_COLOR=1

    log "===== 시작 ====="
    runStep "update" "${brew}" update
    runStep "upgrade" "${brew}" upgrade
    runStep "cleanup" "${brew}" cleanup --prune=30
    log "===== 완료 ====="

    touch "${STAMP}"
}

main "$@"
