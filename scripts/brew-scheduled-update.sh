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
# launchd 는 예약 작업을 맥이 잠깐 깬 상태 (darkwake) 에서 띄우는데, 맥은 수십 초 안에 다시 잠든다.
# 그러면 다운로드가 멈췄다 이어지기를 반복하다 실패하므로, 작업이 끝날 때까지 caffeinate 로 잠자기를 막는다.
#
# pkg 설치기를 쓰는 cask 는 설치·제거에 sudo 비밀번호가 필요해 사람이 없는 예약 실행에서는 늘 실패한다.
# 그런 cask 는 건너뛰고 "손으로 올릴 것" 으로 로그와 알림에 남긴다.
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

# 일시적인 다운로드 실패에 대비한 upgrade 재시도
readonly UPGRADE_ATTEMPTS=2
readonly RETRY_DELAY_SECONDS=60

readonly NOTIFY_TITLE="Homebrew 예약 갱신"
readonly NOTIFY_GROUP="brew-scheduled-update"

failedSteps=()

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
        failedSteps+=("${name}")
        log "!!! brew ${name} 실패 — 다음 단계 계속 진행"
    fi
}

retry() {
    local attempt

    for (( attempt = 1; ; attempt++ )); do
        if "$@"; then
            return 0
        fi

        if (( attempt >= UPGRADE_ATTEMPTS )); then
            return 1
        fi

        log "--- ${RETRY_DELAY_SECONDS}초 뒤 다시 시도 (${attempt}/${UPGRADE_ATTEMPTS})"
        sleep "${RETRY_DELAY_SECONDS}"
    done
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

# terminal-notifier (Brewfile) 로 띄우면 누르면 로그가 열리고, 같은 그룹의 이전 알림을 바꿔 쌓이지 않는다.
# terminal-notifier 는 시스템 설정 > 알림 에서 허용돼 있어야 한다 — 허용되지 않았으면 exit 3 으로 끝난다.
# 그때와 terminal-notifier 가 없을 때는 osascript 로 띄운다 (누르면 스크립트 편집기가 열린다 — 실패 알림 본문이 로그 명령을 담는다).
notify() {
    local notifier

    if notifier=$(findNotifier) \
        && "${notifier}" -title "${NOTIFY_TITLE}" -message "$1 — 누르면 로그" -group "${NOTIFY_GROUP}" -open "file://${LOG}" >/dev/null 2>&1; then
        return 0
    fi

    /usr/bin/osascript - "$1" "${NOTIFY_TITLE}" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
    display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
}

# 갱신할 cask 중 pkg 설치기를 쓰는 것 (sudo 필요) 을 고른다. jq 가 없으면 고르지 않는다.
listSudoCasks() {
    local brew=$1
    local outdated

    command -v jq >/dev/null || return 0
    outdated=$("${brew}" outdated --cask --quiet) || return 0
    [[ -n "${outdated}" ]] || return 0

    # shellcheck disable=SC2086 # cask 이름 목록을 인자로 나눈다
    "${brew}" info --cask --json=v2 ${outdated} \
        | jq -r '.casks[] | select(any(.artifacts[]; has("pkg") or has("installer"))) | .token'
}

# 한 번 시도할 때마다 목록을 새로 구해, 재시도 때는 아직 밀린 것만 올린다
upgradeCasks() {
    local brew=$1
    local sudoCasks=$2
    local casks

    casks=$("${brew}" outdated --cask --quiet | grep -vxF -f <(printf '%s\n' "${sudoCasks}") || true)

    if [[ -z "${casks}" ]]; then
        echo "올릴 cask 없음"
        return 0
    fi

    # shellcheck disable=SC2086 # cask 이름 목록을 인자로 나눈다
    "${brew}" upgrade --cask ${casks}
}

reportResult() {
    local sudoCasks=$1
    local manual=""

    if [[ -n "${sudoCasks}" ]]; then
        manual="brew upgrade --cask ${sudoCasks//$'\n'/ }"
        log "손으로 올릴 것 (sudo 필요): ${manual}"
    fi

    if (( ${#failedSteps[@]} == 0 )); then
        log "결과: 실패한 단계 없음"
    else
        log "결과: 실패한 단계 — ${failedSteps[*]}"
    fi

    if (( ${#failedSteps[@]} > 0 )); then
        notify "실패: ${failedSteps[*]} — make brew-scheduled-update-log 로 확인"
    elif [[ -n "${manual}" ]]; then
        notify "손으로 올릴 것: ${manual}"
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

    # 이 스크립트가 끝날 때까지 맥이 잠들지 않게 한다
    /usr/bin/caffeinate -i -w $$ &

    log "===== 시작 ====="
    runStep "update" "${brew}" update

    local sudoCasks
    sudoCasks=$(listSudoCasks "${brew}") || sudoCasks=""

    runStep "upgrade --formula" retry "${brew}" upgrade --formula
    runStep "upgrade --cask" retry upgradeCasks "${brew}" "${sudoCasks}"
    runStep "cleanup" "${brew}" cleanup --prune=30
    reportResult "${sudoCasks}"
    log "===== 완료 ====="

    touch "${STAMP}"
}

main "$@"
