#!/usr/bin/env bash
#
# 이 장비의 상태 점검 (dotfiles-doctor 의 machine.sh) 을 주 1회 돌리는 예약 작업 (launchd: com.socoolbear.dotfiles-machine-check).
#
# 고치기 (2026-11-23 사용자 결정) — machine.sh 는 읽기 전용으로 두고, 그 출력에서 아래 고정 문구를 찾았을 때만 여기서 고친다.
# 모델 없이 결과가 정해져 있고, 사용자 데이터 · 비밀값 · 설정을 바꾸지 않고, 다시 돌려도 같은 것만 넣는다 (나머지는 알리기만):
#   - dotfiles 의 launchd 작업이 등록되지 않음 → scripts/launchd-agents.sh sync (make sync 의 launchd 단계만 — 실행 중인 작업은 그 스크립트가 건너뛴다)
#   - dotfiles 자동 갱신이 며칠째 돌지 않음   → dotfiles-auto-update 한 번 (그 스크립트의 안전 조건 · 잠금을 그대로 탄다)
# 고친 것이 있으면 점검을 다시 돌리고, 다시 돌린 결과에 그 문구가 없으면 "고친 것", 남았으면 "직접 확인이 필요한 것" 으로 메일에 적는다.
# 끄기: DOTFILES_MACHINE_CHECK_FIX=0 (점검 · 메일만). 손으로 돌리는 make machine-check 도 같은 동작이다 (고치는 범위가 make sync · 자동 갱신과 같다).
#
# 점검 출력은 로그에 남기고, 고친 것이 있거나 FAIL · WARN 이 1건 이상일 때만 메일 한 통을 보낸다 (macOS 알림은 띄우지 않는다 — 2026-11-21 사용자 결정).
# 메일은 "고친 것 / 직접 확인이 필요한 것" 두 묶음이다. 자동 갱신과 함께 쓰는 scripts/send-mail.sh (claude -p + claude.ai 의 Gmail 커넥터) 로 보낸다.
# 받는 주소는 git config user.email 이고, 로그 · 저장소에 적지 않는다.
# 점검 항목 줄에는 서버 이름 · 경로가 섞일 수 있어 메일에는 건수 · 항목이 나온 영역 제목 (machine.sh 의 고정 문구) · 고친 것의 고정 문구만 넣는다.
#
# 발송에 실패하면 다른 알림 없이 로그에 남기고 실패 표시 파일을 둔다. 다음 machine.sh 가 그 파일을 WARN 으로 내고,
# 세션 시작 때의 doctor 제안 (suggest.sh) 도 그 파일을 본다. 다음 발송이 성공하면 파일을 지운다.
#
# launchd 는 PATH 가 /usr/bin:/bin:/usr/sbin:/sbin 뿐이라 Homebrew · mise 의 명령 (claude · gh · npm · node · jq) 을 못 찾는다.
# 그래서 여기서 PATH 를 채운다. 그래도 없는 명령은 machine.sh 가 WARN 으로 낸다.
#
# 즉시 실행: dotfiles-machine-check (make machine-check)
# 메일만 시험: dotfiles-machine-check --test-mail (두 묶음 본문의 예를 "(시험)" 제목으로 — 점검 · 고치기는 하지 않음)

set -euo pipefail

readonly LOG="${HOME}/Library/Logs/dotfiles-machine-check.log"
readonly MAX_LOG_BYTES=$((1024 * 1024))
readonly MAIL_FAILED_FLAG="${HOME}/.local/state/dotfiles-machine-check/mail-failed"
readonly CLAUDE_BIN="${MACHINE_CHECK_CLAUDE:-claude}"   # 실패 경로 시험용으로 바꿀 수 있다
readonly FIX_ENABLED="${DOTFILES_MACHINE_CHECK_FIX:-1}"
readonly FIX_NAMES="launchd auto-update"   # 이 순서로 고친다 — 자동 갱신 작업이 빠졌으면 다시 건 뒤에 갱신을 돌린다

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

#--------------------------------------------------------------------------
# 고치기 — 이름마다 찾는 문구 (machine.sh 출력의 고정 문구) · 고치는 명령 · 메일에 넣는 고정 문구
#--------------------------------------------------------------------------

# 인자: 고칠 것 이름. machine.sh 출력에서 찾는 문구 (grep -E). 고친 뒤 다시 돌린 점검에 이 문구가 없으면 고친 것이다
fixPattern() {
    case "$1" in
        (launchd) printf '%s' '^\[FAIL\] launchd 작업이 등록되지 않음: ' ;;
        (auto-update) printf '%s' '^\[WARN\] dotfiles 자동 갱신: [0-9]+일 넘게 돌지 않음' ;;
    esac
}

# 인자: 고칠 것 이름. 고쳤을 때 메일에 넣는 한 줄
fixedText() {
    case "$1" in
        (launchd) printf '%s' "등록되지 않은 dotfiles 예약 작업을 다시 걸었습니다 (make sync 의 launchd 단계)" ;;
        (auto-update) printf '%s' "며칠째 돌지 않은 dotfiles 자동 갱신을 한 번 돌렸습니다 (결과: make auto-update-log)" ;;
    esac
}

# 인자: 고칠 것 이름. 고치려 했지만 남았을 때 메일에 넣는 한 줄
leftText() {
    case "$1" in
        (launchd) printf '%s' "등록되지 않은 dotfiles 예약 작업 — 다시 걸었지만 여전히 등록되지 않음 (make sync)" ;;
        (auto-update) printf '%s' "며칠째 돌지 않은 dotfiles 자동 갱신 — 한 번 돌렸지만 그대로임 (make auto-update-log)" ;;
    esac
}

# 인자: 저장소, 고칠 것 이름. 출력은 로그로 보낸다
runFix() {
    case "$2" in
        (launchd) bash "$1/scripts/launchd-agents.sh" sync ;;
        (auto-update) bash "$1/scripts/dotfiles-auto-update.sh" ;;
    esac
}

# 인자: 저장소, 점검 출력. 찾는 문구가 나온 것을 고치고, 고치려 한 이름을 한 줄에 하나씩 출력한다
runFixes() {
    local dotfiles=$1
    local output=$2
    local name exitCode

    for name in ${FIX_NAMES}; do
        grep -qE "$(fixPattern "${name}")" <<<"${output}" || continue

        log "고치기: ${name} 시작"
        exitCode=0
        runFix "${dotfiles}" "${name}" >>"${LOG}" 2>&1 || exitCode=$?
        log "고치기: ${name} 끝 (exit ${exitCode})"
        printf '%s\n' "${name}"
    done
}

#--------------------------------------------------------------------------
# 메일
#--------------------------------------------------------------------------

# 인자: 장비 이름, 고친 건수, 고친 것 줄들, FAIL 건수, WARN 건수, 직접 확인할 것 줄들. 메일 본문을 출력한다
mailBody() {
    printf '%s\n' \
        "$1 의 주 1회 장비 점검 결과입니다 ($(date '+%Y-%m-%d %H:%M'))." \
        "" \
        "고친 것 ($2건)" \
        "${3:-- 없음}" \
        "" \
        "직접 확인이 필요한 것 (FAIL $4건 · WARN $5건)" \
        "${6:-- 없음}" \
        "" \
        "자세한 내용: make machine-check-log" \
        "직접 확인: Claude Code 에서 \"dotfiles 점검해줘\" (dotfiles-doctor)"
}

# 인자: 저장소, 고치려 한 이름 목록 (줄마다 하나), 마지막 점검 출력.
# 고친 것이 있거나 FAIL · WARN 이 1건 이상이면 메일을 보내고 결과를 로그 · 실패 표시 파일에 남긴다
mailResult() {
    local dotfiles=$1
    local attempted=$2
    local output=$3
    local failCount warnCount
    failCount=$(grep -c '^\[FAIL\]' <<<"${output}" || true)
    warnCount=$(grep -c '^\[WARN\]' <<<"${output}" || true)

    local name fixedLines="" leftLines="" fixedCount=0

    for name in ${attempted}; do
        if grep -qE "$(fixPattern "${name}")" <<<"${output}"; then
            leftLines+="- 고치려 했지만 남음: $(leftText "${name}")"$'\n'
        else
            fixedLines+="- $(fixedText "${name}")"$'\n'
            fixedCount=$(( fixedCount + 1 ))
        fi
    done

    if (( fixedCount + failCount + warnCount == 0 )); then
        log "메일: 보내지 않음 (고친 것 · FAIL · WARN 없음)"
        return 0
    fi

    local areas
    areas=$(listProblemAreas "${output}")
    (( failCount + warnCount == 0 )) || leftLines+="- 항목이 나온 영역: ${areas}"$'\n'
    fixedLines=${fixedLines%$'\n'}
    leftLines=${leftLines%$'\n'}

    local machine subject body
    machine=$(machineName)
    subject="dotfiles 장비 점검: 고친 것 ${fixedCount} · 직접 확인 $(( failCount + warnCount ))건 (${machine})"
    body=$(mailBody "${machine}" "${fixedCount}" "${fixedLines}" "${failCount}" "${warnCount}" "${leftLines}")

    local reason
    if reason=$(sendMail "${dotfiles}" "${subject}" "${body}"); then
        rm -f "${MAIL_FAILED_FLAG}"
        log "메일: 보냄 (고친 것 ${fixedCount}건)"
    else
        markMailFailed "${reason}"
    fi
}

# 인자: 저장소. machine.sh 를 돌려 출력을 로그에 남기고 출력한다
runCheck() {
    local output
    output=$(DOTFILES="$1" bash "$1/.claude/skills/dotfiles-doctor/scripts/machine.sh" 2>&1) || true
    printf '%s\n' "${output}" >>"${LOG}"
    printf '%s' "${output}"
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
        local machine body
        machine=$(machineName)
        body=$(printf '%s\n\n' "시험 메일입니다 — 아래는 꼴을 보이려는 예이고 실제 점검 결과가 아닙니다."
            mailBody "${machine}" 1 "- $(fixedText launchd)" 0 1 "- 항목이 나온 영역: 6. 비밀값 사본 (예)")

        if reason=$(sendMail "${dotfiles}" "dotfiles 장비 점검 (시험): 고친 것 1 · 직접 확인 1건 (${machine})" "${body}"); then
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

    local output attempted=""
    output=$(runCheck "${dotfiles}")

    if [[ "${FIX_ENABLED}" == "0" ]]; then
        log "고치기: 꺼짐 (DOTFILES_MACHINE_CHECK_FIX=0)"
    else
        attempted=$(runFixes "${dotfiles}" "${output}")
    fi

    if [[ -n "${attempted}" ]]; then
        log "고친 뒤 점검을 다시 돌림"
        output=$(runCheck "${dotfiles}")
    fi

    local failCount warnCount
    failCount=$(grep -c '^\[FAIL\]' <<<"${output}" || true)
    warnCount=$(grep -c '^\[WARN\]' <<<"${output}" || true)

    log "결과: FAIL ${failCount}건 · WARN ${warnCount}건 · 고치려 한 것: $(paste -sd ' ' - <<<"${attempted:-없음}")"
    mailResult "${dotfiles}" "${attempted}" "${output}"
    log "===== 완료 ====="
}

main "$@"
