#!/usr/bin/env bash
#
# 잠자기 방지 (sleepguard) 1 회성 셋업 — 새 장비에서 `make sleepguard` 로 실행.
#
# 심볼릭 링크로 관리할 수 없어 여기서 "생성" 해야 하는 두 가지를 처리한다.
#   1. /etc/sudoers.d/pmset-sleep — root:wheel 440 이어야 해서 dotfiles 심링크 불가
#   2. SwiftBar 플러그인 폴더 지정 — 앱 환경설정 (defaults) 이라 파일로 관리 불가
#
# 문법이 깨진 파일이 /etc/sudoers.d 에 잠깐이라도 놓이면 시스템 전체 sudo 가 망가진다.
# 그래서 임시 파일에서 visudo -cf 검증을 통과한 뒤에만 설치한다 (검증 후 설치 순서 고정).
#
# 플러그인 자체는 `make sync` 가 ~/.swiftbar-plugins 로 심링크한다.

set -euo pipefail

readonly SUDOERS_FILE=/etc/sudoers.d/pmset-sleep
readonly PLUGIN_DIR="${HOME}/.swiftbar-plugins"
readonly SWIFTBAR_DOMAIN=com.ameba.SwiftBar

step() { printf '==> %s\n' "$1"; }

#--------------------------------------------------------------------------
# sudoers NOPASSWD 룰
#--------------------------------------------------------------------------

# sudo -l 은 명령을 실행하지 않고 허용 여부만 확인한다 (disablesleep 상태를 건드리지 않음)
hasSudoersRule() {
    sudo -n -l /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 &&
        sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1
}

installSudoersRule() {
    local tmp
    tmp=$(mktemp)

    # 와일드카드 대신 실제로 쓰는 두 명령만 허용한다
    printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' \
        "$(whoami)" >"${tmp}"

    if ! visudo -cf "${tmp}" >/dev/null; then
        rm -f "${tmp}"
        echo "ERROR: sudoers 룰 문법 검증 실패 — 설치하지 않았습니다." >&2
        return 1
    fi

    echo "    관리자 비밀번호가 필요합니다 (${SUDOERS_FILE} 생성)."
    sudo install -m 440 -o root -g wheel "${tmp}" "${SUDOERS_FILE}"
    rm -f "${tmp}"
}

setupSudoers() {
    if hasSudoersRule; then
        step "sudoers 룰 이미 등록됨 — 건너뜀"
        return 0
    fi

    step "sudoers 룰 등록 (${SUDOERS_FILE})"
    installSudoersRule

    if ! hasSudoersRule; then
        echo "ERROR: 룰을 설치했으나 sudo -n 이 여전히 실패합니다. 사용자명 / pmset 경로를 확인하세요." >&2
        return 1
    fi
}

#--------------------------------------------------------------------------
# SwiftBar
#--------------------------------------------------------------------------

currentPluginDirectory() {
    defaults read "${SWIFTBAR_DOMAIN}" PluginDirectory 2>/dev/null || true
}

restartSwiftBar() {
    pgrep -x SwiftBar >/dev/null || return 0

    step "SwiftBar 재시작 (플러그인 폴더 변경 반영)"
    killall SwiftBar 2>/dev/null || true
    sleep 1
    open -a SwiftBar
}

setupSwiftBar() {
    if [[ ! -d /Applications/SwiftBar.app ]]; then
        echo "ERROR: SwiftBar 가 없습니다. 'make brew-apps' 로 먼저 설치하세요." >&2
        return 1
    fi

    if [[ "$(currentPluginDirectory)" == "${PLUGIN_DIR}" ]]; then
        step "SwiftBar 플러그인 폴더 이미 지정됨 — 건너뜀"
        return 0
    fi

    step "SwiftBar 플러그인 폴더 지정 (${PLUGIN_DIR})"
    defaults write "${SWIFTBAR_DOMAIN}" PluginDirectory -string "${PLUGIN_DIR}"
    defaults write "${SWIFTBAR_DOMAIN}" MakePluginExecutable -bool true
    restartSwiftBar
}

#--------------------------------------------------------------------------

main() {
    if [[ ! -L "${PLUGIN_DIR}" ]]; then
        echo "ERROR: ${PLUGIN_DIR} 가 심볼릭 링크가 아닙니다. 'make sync' 를 먼저 실행하세요." >&2
        exit 1
    fi

    setupSudoers
    setupSwiftBar

    echo ""
    echo "==> 완료. 메뉴바 아이콘으로 잠자기 방지를 토글하세요."
    echo "    원복:      sudo pmset -a disablesleep 0"
    echo "    룰 제거:   sudo rm ${SUDOERS_FILE}"
}

main "$@"
