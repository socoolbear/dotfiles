#!/usr/bin/env bash
#
# 잠자기 방지 (pmset disablesleep) 토글 + 자동 해제 타이머.
# SwiftBar 플러그인 (swiftbar/sleepguard.5s.sh) 이 ~/.local/bin/sleepguard 로 호출한다.
#
# caffeinate 는 sudo 없이 되지만 뚜껑을 닫은 상태 (clamshell) 를 막지 못한다.
# 그래서 disablesleep 이 필요하고, 그래서 root 권한이 필요하다.
# 권한은 /etc/sudoers.d/pmset-sleep 의 NOPASSWD 룰이 담당한다 (scripts/sleepguard-setup.sh 가 설치).
#
# SleepDisabled 는 재부팅해도 유지되므로, 켠 채 잊으면 배터리로 가방에 넣었을 때 발열·방전 위험이 있다.
# 그래서 만료 시각을 파일에 적어두고, 플러그인의 5 초 폴링이 tick 으로 만료를 확인해 스스로 해제한다.
#
# 사용법:
#   sleepguard on [minutes]   # minutes 생략 시 무제한
#   sleepguard off
#   sleepguard tick           # 만료됐으면 해제 (플러그인이 폴링마다 호출)
#   sleepguard remaining      # 남은 시간 문구 출력

set -euo pipefail

readonly PMSET=/usr/bin/pmset
readonly STATE_DIR="${HOME}/.local/state/sleepguard"
readonly EXPIRES_AT="${STATE_DIR}/expires-at"

isEnabled() {
    [[ "$(${PMSET} -g | awk '/SleepDisabled/{print $2}')" == "1" ]]
}

setSleepDisabled() {
    local value=$1

    sudo -n "${PMSET}" -a disablesleep "${value}"
}

enableGuard() {
    local minutes=${1:-0}

    if ! [[ "${minutes}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: minutes 는 0 이상의 정수여야 합니다 — '${minutes}'" >&2
        return 1
    fi

    setSleepDisabled 1
    mkdir -p "${STATE_DIR}"

    if (( minutes > 0 )); then
        date -v"+${minutes}M" '+%s' >"${EXPIRES_AT}"
    else
        rm -f "${EXPIRES_AT}"
    fi
}

disableGuard() {
    setSleepDisabled 0
    rm -f "${EXPIRES_AT}"
}

# 만료 확인 전용 — 예약이 없거나 아직 남았으면 아무것도 하지 않는다
tickGuard() {
    if ! isEnabled; then
        rm -f "${EXPIRES_AT}"
        return 0
    fi

    [[ -f "${EXPIRES_AT}" ]] || return 0

    local now expires
    now=$(date '+%s')
    expires=$(cat "${EXPIRES_AT}")

    (( now >= expires )) || return 0

    disableGuard
}

remainingLabel() {
    if [[ ! -f "${EXPIRES_AT}" ]]; then
        echo "무제한"
        return 0
    fi

    local left
    left=$(( $(cat "${EXPIRES_AT}") - $(date '+%s') ))
    (( left < 0 )) && left=0

    if (( left >= 3600 )); then
        printf '%d시간 %d분 남음\n' $(( left / 3600 )) $(( left % 3600 / 60 ))
    else
        printf '%d분 남음\n' $(( left / 60 ))
    fi
}

main() {
    local command=${1:-}

    case "${command}" in
        on)        enableGuard "${2:-0}" ;;
        off)       disableGuard ;;
        tick)      tickGuard || true ;;   # 플러그인 출력이 깨지지 않도록 실패를 흡수
        remaining) remainingLabel ;;
        *)
            echo "사용법: sleepguard {on [minutes]|off|tick|remaining}" >&2
            exit 1
            ;;
    esac
}

main "$@"
