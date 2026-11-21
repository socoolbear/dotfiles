#!/usr/bin/env bash
#
# make sync / make clean 이 부른다 — dotfiles 의 launchd 예약 작업을 이 장비에 걸고 내린다.
#
#   launchd-agents.sh sync   launchd/*.plist 틀마다 ~/Library/LaunchAgents/ 에 plist 를 만들어 다시 걸고,
#                            dotfiles 가 걸었다가 저장소에서 지운 작업을 내리고 치운다
#   launchd-agents.sh clean  dotfiles 가 건 작업을 모두 내리고 plist 를 치운다
#
# 왜 심링크가 아니라 생성인가:
#   로그인 항목 > 백그라운드 항목 목록은 plist 가 실행하는 파일 (ProgramArguments 첫 칸) 의 이름을 보여 준다.
#   plist 는 $HOME 을 풀지 못해, 예전처럼 /bin/bash -c 를 거치면 셋 다 "bash" 로 떴다.
#   그래서 틀의 @HOME@ 을 이 장비의 홈 경로로 채워 ~/.local/bin/<이름> 을 직접 부르게 만든다 (저장소에는 틀만 둔다).
#
# 자동 정리가 지우는 것 (라벨이 com.socoolbear. 로 시작하고 틀이 없는 것 가운데):
#   - 이 저장소의 launchd/ 를 가리키는 끊긴 심링크 (생성 방식 이전에 걸었던 것)
#   - 아래 GENERATED_MARK 줄이 든 파일 (이 스크립트가 만든 것)
# 둘 다 아니면 남의 것으로 보고 건드리지 않는다.

set -euo pipefail

readonly DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly LABEL_PREFIX="com.socoolbear."
readonly GENERATED_MARK="<!-- dotfiles-generated: make sync 가 dotfiles 의 launchd/ 틀로 만든 파일 — 고치려면 틀을 고치고 make sync -->"

# 실행 중인 작업은 bootout 하지 않는다 (isRunningJob) — 자동 갱신이 부른 make sync 는 DOTFILES_AUTO_UPDATE_RUNNING=1 로 알린다
readonly AUTO_UPDATE_LABEL="com.socoolbear.dotfiles-auto-update"

log() {
    echo "==> launchd: $*"
}

# 지우기 전에 홈 경로를 확인한다 — 빈 값 · / · 없는 폴더면 아무것도 하지 않는다.
# XML 에 그대로 넣을 수 없는 문자가 든 경로도 거부한다 (틀에 채워 넣으므로)
requireSafeHome() {
    if [[ -z "${HOME:-}" || "${HOME}" == "/" || "${HOME}" != /* || ! -d "${HOME}" ]]; then
        echo "ERROR: HOME 이 비었거나 안전하지 않습니다 (${HOME:-빈 값}) — launchd 작업을 건드리지 않습니다" >&2
        exit 1
    fi

    if [[ "${HOME}" == *[\&\<\>\|\\]* ]]; then
        echo "ERROR: HOME 경로에 plist 에 넣을 수 없는 문자가 있습니다 (${HOME})" >&2
        exit 1
    fi
}

# 인자: 라벨. launchd 에 걸려 있는가
isLoaded() {
    launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1
}

# 인자: 라벨. 지금 실행 중인가 — 실행 중인 작업을 bootout 하면 launchd 가 죽인다 (brew upgrade · 자동 갱신이 중간에 끊긴다).
# 이 프로세스를 띄운 작업 (launchd 는 띄운 작업의 라벨을 XPC_SERVICE_NAME 에 넣는다) · 자동 갱신이 부른 make sync ·
# launchd 가 running 으로 보는 작업 (launchctl print 의 맨 위 "state = running" 줄) 이 그렇다
isRunningJob() {
    local label=$1
    local printed

    [[ "${label}" == "${XPC_SERVICE_NAME:-}" ]] && return 0
    [[ -n "${DOTFILES_AUTO_UPDATE_RUNNING:-}" && "${label}" == "${AUTO_UPDATE_LABEL}" ]] && return 0

    printed=$(launchctl print "gui/$(id -u)/${label}" 2>/dev/null) || return 1
    grep -qx $'\tstate = running' <<<"${printed}"
}

# 인자: 틀 경로, 출력 경로. 첫 줄 (XML 선언) 다음에 표식을 넣고 @HOME@ 을 홈 경로로 채운다
render() {
    local template=$1
    local output=$2

    awk -v mark="${GENERATED_MARK}" -v home="${HOME}" '
        NR == 1 { print; print mark; next }
        { gsub(/@HOME@/, home); print }
    ' "${template}" >"${output}"
}

# 인자: 놓일 plist 경로. 이 저장소의 launchd/ 를 가리키는 링크이거나 표식이 든 파일이면 dotfiles 것이다
isDotfilesAgent() {
    local plist=$1

    if [[ -L "${plist}" ]]; then
        [[ "$(readlink "${plist}")" == "${DOTFILES}/launchd/"* ]]
        return
    fi

    [[ -f "${plist}" ]] && grep -qxF "${GENERATED_MARK}" "${plist}"
}

# 인자: 라벨, 사유. 작업을 내리고 plist 를 치운다 (경로는 고정 폴더 + 고정 접두사 + 라벨로만 만든다)
removeAgent() {
    local label=$1
    local reason=$2
    local plist="${HOME}/Library/LaunchAgents/${label}.plist"

    if isRunningJob "${label}"; then
        log "${label}: 지금 실행 중인 작업이라 이번에는 치우지 않음 (${reason})"
        return
    fi

    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    rm -f -- "${plist}"
    log "${label}: 내리고 plist 를 치움 (${reason})"
}

# 인자: 라벨. 놓인 plist 를 건다
bootstrapAgent() {
    local label=$1

    launchctl bootstrap "gui/$(id -u)" "${HOME}/Library/LaunchAgents/${label}.plist" 2>/dev/null \
        || log "${label}: 등록 실패 (launchctl bootstrap)"
}

# 인자: 틀 경로. 만든 내용이 지금 것과 다를 때만 바꿔 놓고 다시 건다 (심링크였으면 파일로 바뀐다).
# 내용이 같으면 걸려 있지 않을 때만 건다. 내용이 다른데 작업이 실행 중이면 파일도 바꾸지 않고 넘긴다 —
# 놓인 plist 가 틀과 계속 달라서 다음 make sync 가 다시 시도한다
installAgent() {
    local template=$1
    local label
    label=$(basename "${template}" .plist)
    local agents_dir="${HOME}/Library/LaunchAgents"
    local plist="${agents_dir}/${label}.plist"
    local staged

    staged=$(mktemp "${agents_dir}/.${label}.XXXXXX") || { log "${label}: 임시 파일을 만들지 못해 건너뜀"; return; }
    render "${template}" "${staged}"

    if ! plutil -lint -s "${staged}"; then
        rm -f -- "${staged}"
        log "${label}: 만든 plist 가 읽히지 않아 건너뜀 (틀 확인)"
        return
    fi

    if [[ ! -L "${plist}" ]] && cmp -s "${staged}" "${plist}"; then
        rm -f -- "${staged}"
        isLoaded "${label}" || bootstrapAgent "${label}"
        return
    fi

    if isRunningJob "${label}"; then
        rm -f -- "${staged}"
        log "${label}: 예약 설정이 바뀌었지만 지금 실행 중이라 다시 걸지 않음 — 다음 make sync 때 다시 걸림"
        return
    fi

    chmod 644 "${staged}"
    mv -f -- "${staged}" "${plist}"
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    bootstrapAgent "${label}"
}

sync() {
    local agents_dir="${HOME}/Library/LaunchAgents"
    local template plist label

    mkdir -p "${agents_dir}"

    for template in "${DOTFILES}/launchd/${LABEL_PREFIX}"*.plist; do
        [[ -f "${template}" ]] || continue
        installAgent "${template}"
    done

    for plist in "${agents_dir}/${LABEL_PREFIX}"*.plist; do
        [[ -e "${plist}" || -L "${plist}" ]] || continue
        label=$(basename "${plist}" .plist)
        [[ -f "${DOTFILES}/launchd/${label}.plist" ]] && continue

        if [[ -L "${plist}" && ! -e "${plist}" ]] && isDotfilesAgent "${plist}"; then
            removeAgent "${label}" "저장소에서 지운 작업 — 끊긴 심링크"
        elif [[ ! -L "${plist}" ]] && isDotfilesAgent "${plist}"; then
            removeAgent "${label}" "저장소에서 지운 작업 — dotfiles 가 만든 plist"
        fi
    done
}

clean() {
    local agents_dir="${HOME}/Library/LaunchAgents"
    local plist label

    for plist in "${agents_dir}/${LABEL_PREFIX}"*.plist; do
        [[ -e "${plist}" || -L "${plist}" ]] || continue
        isDotfilesAgent "${plist}" || continue
        label=$(basename "${plist}" .plist)
        removeAgent "${label}" "make clean"
    done
}

main() {
    requireSafeHome

    case "${1:-}" in
        sync) sync ;;
        clean) clean ;;
        *)
            echo "사용법: $0 sync|clean" >&2
            exit 2
            ;;
    esac
}

main "$@"
