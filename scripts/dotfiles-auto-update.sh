#!/usr/bin/env bash
#
# dotfiles · cc-marketplace 체크아웃 · Claude 플러그인을 Claude 세션과 별개로 하루 1회 갱신하는 예약 작업
# (launchd: com.socoolbear.dotfiles-auto-update).
#
# 안전할 때만 조용히 받고, 못 받았으면 상태 파일에 "손 필요" 로 적는다. 메뉴 막대 (swiftbar/dotfiles-update.5m.sh) 와
# 주 1회 장비 점검 (dotfiles-doctor 의 machine.sh) 이 그 파일을 읽어 알린다. 평소에는 아무것도 띄우지 않는다.
#
# 저장소 (dotfiles · cc-marketplace 체크아웃) 를 받는 조건 — 셋 다 맞을 때만 git merge --ff-only:
#   1. 미커밋 · 미추적 변경이 없다   2. 기본 브랜치에 있다   3. 원격보다 앞선 로컬 커밋이 없다
# 하나라도 어긋나면 작업 트리를 건드리지 않는다 (fetch 만 한다). reset · checkout -- · stash · clean 은 쓰지 않는다.
# 받기 전 커밋은 로그에 남긴다. 되돌리기는 사람이 한다 (git reset --keep <커밋>).
#
# dotfiles 를 받으면 make sync 를 돌린다. Brewfile 이 바뀌었으면 설치하지 않고 "make update 필요" 로만 적는다.
#
# 스스로를 갱신하는 스크립트다. dotfiles 를 받은 뒤에는 새 판을 exec 로 다시 불러 나머지 단계를 새 판이 하게 한다
# (DOTFILES_AUTO_UPDATE_STAGE=after-dotfiles). 끝줄은 `main "$@"; exit $?` 한 줄이라, 파일이 바뀌어도 그 뒤를 읽지 않는다.
#
# make sync 는 launchd 작업을 bootout · bootstrap 으로 다시 건다. 실행 중인 작업을 bootout 하면 launchd 가 그 작업을 죽이므로,
# 여기서 부른 make sync 는 DOTFILES_AUTO_UPDATE_RUNNING=1 을 받아 이 작업의 다시 걸기를 건너뛴다 (Makefile 의 sync).
#
# 무인 실행에서 1Password SSH 에이전트의 승인 창이 뜨지 않도록 GitHub 의 SSH 원격 (git@github.com:) 은 HTTPS 로 바꿔 받는다
# (받기만 하므로 공개 저장소면 인증이 필요 없다). 그래도 SSH 로 남는 원격 (다른 호스트 · ssh 설정의 별칭) 은 받지 않고 손 필요로 둔다.
#
# 사용:
#   dotfiles-auto-update                  지금 갱신 (make auto-update · 메뉴 막대의 "지금 업데이트" 도 같다)
#   dotfiles-auto-update --status         상태 파일을 사람이 읽기 좋게 출력
#   dotfiles-auto-update --dismiss <대상>  "손 필요" 표시 하나를 지운다 (Brewfile 표시처럼 사람이 확인하고 넘길 것)

set -euo pipefail

readonly STATE_DIR="${HOME}/.local/state/dotfiles-update"
readonly STATUS="${STATE_DIR}/status"
readonly LOCK="${STATE_DIR}/lock"
readonly SYNC_PENDING="${STATE_DIR}/sync-pending"
readonly LOG="${HOME}/Library/Logs/dotfiles-auto-update.log"
readonly MAX_LOG_BYTES=$((1024 * 1024))
readonly FETCH_TIMEOUT_SECONDS=60
readonly CLAUDE_TIMEOUT_SECONDS=180
readonly SWIFTBAR_PLUGIN="dotfiles-update"
# 실패 경로 시험용으로 바꿀 수 있다 (없는 명령 이름을 넣어 "명령 없음" 을 시험)
readonly CLAUDE_BIN="${DOTFILES_AUTO_UPDATE_CLAUDE:-claude}"
readonly REQUIRED_COMMANDS="${DOTFILES_AUTO_UPDATE_REQUIRE:-git make}"

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

#--------------------------------------------------------------------------
# 상태 파일 — 탭으로 나눈 줄. 대상 줄: <대상> <상태> <설명> <그 상태가 시작된 epoch>
#   상태: latest (최신) · updated (받음) · manual (손 필요) · failed (실패) · skipped (없어서 건너뜀)
#         · unreachable (원격에 닿지 못함 — 깨어난 직후 · 오프라인일 수 있어 메뉴 막대는 하루 넘게 이어질 때만 띄운다)
#   last_run 줄: last_run <시각> <epoch>
#--------------------------------------------------------------------------

# 인자: 대상, 상태, 설명. 같은 상태가 이어지면 시작 시각을 그대로 둔다 (장비 점검이 "N일째" 를 센다)
setStatus() {
    local target=$1
    local state=$2
    local detail=$3
    local now since=""
    now=$(date +%s)

    if [[ -f "${STATUS}" ]]; then
        since=$(awk -F'\t' -v t="${target}" -v s="${state}" '$1 == t && $2 == s { print $4 }' "${STATUS}")
    fi

    writeStatusLine "${target}" "${target}"$'\t'"${state}"$'\t'"${detail}"$'\t'"${since:-${now}}"
    log "${target}: ${state} — ${detail}"
}

# 인자: 첫 칸 값, 바꿔 넣을 줄 (빈 값이면 그 줄을 지운다)
writeStatusLine() {
    local key=$1
    local line=$2
    local tmp="${STATUS}.tmp.$$"

    { [[ -f "${STATUS}" ]] && awk -F'\t' -v k="${key}" '$1 != k' "${STATUS}"; [[ -z "${line}" ]] || printf '%s\n' "${line}"; } >"${tmp}"
    mv -f "${tmp}" "${STATUS}"
}

printStatus() {
    if [[ ! -f "${STATUS}" ]]; then
        echo "아직 실행 기록이 없습니다 (make auto-update)."
        return 0
    fi

    awk -F'\t' '
        $1 == "last_run" { print "마지막 실행: " $2; next }
        { label = ($2 == "latest" ? "최신" : $2 == "updated" ? "받음" : $2 == "manual" ? "손 필요" : $2 == "failed" ? "실패" : $2 == "unreachable" ? "받아오지 못함" : "건너뜀")
          print $1 ": " label " — " $3 }
    ' "${STATUS}"
}

#--------------------------------------------------------------------------
# 잠금 — 실행이 겹치지 않게. exec 로 새 판을 불러도 pid 가 같으므로 잠금을 그대로 이어 쓴다
#--------------------------------------------------------------------------

acquireLock() {
    local holder

    if mkdir "${LOCK}" 2>/dev/null; then
        echo $$ >"${LOCK}/pid"
        return 0
    fi

    holder=$(cat "${LOCK}/pid" 2>/dev/null || true)

    if [[ "${holder}" == "$$" ]]; then
        return 0
    fi

    if [[ -n "${holder}" ]] && kill -0 "${holder}" 2>/dev/null; then
        return 1
    fi

    rm -rf "${LOCK}"
    mkdir "${LOCK}" && echo $$ >"${LOCK}/pid"
}

# shellcheck disable=SC2329 # trap 으로 부른다
releaseLock() {
    [[ "$(cat "${LOCK}/pid" 2>/dev/null || true)" == "$$" ]] && rm -rf "${LOCK}"
    return 0
}

#--------------------------------------------------------------------------
# git 저장소 받기
#--------------------------------------------------------------------------

# 무인 실행용 git 환경 — 비밀번호 입력을 띄우지 않고 곧바로 실패하게 하고, GitHub SSH 원격을 HTTPS 로 받는다. claude · make 가 부르는 git 도 따른다
exportUnattendedGit() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf"
    export GIT_CONFIG_VALUE_0="git@github.com:"
    export GIT_CONFIG_KEY_1="url.https://github.com/.insteadOf"
    export GIT_CONFIG_VALUE_1="ssh://git@github.com/"
}

# 인자: 저장소. origin 의 기본 브랜치 이름 (origin/HEAD, 없으면 main · master 중 있는 것)
defaultBranch() {
    local repo=$1
    local head candidate

    if head=$(git -C "${repo}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
        echo "${head#origin/}"
        return 0
    fi

    for candidate in main master; do
        if git -C "${repo}" rev-parse --verify --quiet "refs/remotes/origin/${candidate}" >/dev/null; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

# 인자: 원격 주소. 사람 손 (승인 창 · 비밀번호) 없이 받을 수 있는 주소인가
isUnattendedUrl() {
    case "$1" in
        https://* | http://* | file://* | /*) return 0 ;;
        *) return 1 ;;
    esac
}

# 인자: 대상 이름, 저장소. 받으면 0 을 돌려주고 받기 전 커밋을 PULLED_FROM 에 남긴다 (받지 않았으면 비운다)
updateRepo() {
    local target=$1
    local repo=$2
    PULLED_FROM=""

    # SSH 로 받으면 1Password 승인 창이 뜰 수 있다 — insteadOf 를 거친 뒤에도 HTTPS · 로컬 경로가 아니면 받지 않는다
    local url
    url=$(git -C "${repo}" ls-remote --get-url origin 2>/dev/null || true)

    if ! isUnattendedUrl "${url}"; then
        setStatus "${target}" manual "SSH 원격이라 무인으로 받지 않음 (승인 창이 뜰 수 있음) — 직접 git pull 하거나 원격을 HTTPS 로"
        return 1
    fi

    local fetchError
    if ! fetchError=$(runLimited "${FETCH_TIMEOUT_SECONDS}" git -C "${repo}" fetch --quiet origin 2>&1); then
        setStatus "${target}" unreachable "원격에서 받아오지 못함 (네트워크 · 원격 주소 확인): $(head -n 1 <<<"${fetchError}" | cut -c1-120)"
        return 1
    fi

    local branch current
    if ! branch=$(defaultBranch "${repo}"); then
        setStatus "${target}" failed "원격의 기본 브랜치를 찾지 못함"
        return 1
    fi

    current=$(git -C "${repo}" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(브랜치 아님)")

    local behind ahead
    behind=$(git -C "${repo}" rev-list --count "HEAD..origin/${branch}")
    ahead=$(git -C "${repo}" rev-list --count "origin/${branch}..HEAD")

    local waiting=""
    (( behind == 0 )) || waiting=" · 받을 커밋 ${behind}개"

    if [[ -n "$(git -C "${repo}" status --porcelain 2>/dev/null)" ]]; then
        setStatus "${target}" manual "미커밋 · 미추적 변경이 있음 — 그 저장소에서 직접 정리${waiting}"
        return 1
    fi

    if [[ "${current}" != "${branch}" ]]; then
        setStatus "${target}" manual "기본 브랜치 (${branch}) 가 아닌 ${current} 에 있음${waiting}"
        return 1
    fi

    if (( ahead > 0 )); then
        setStatus "${target}" manual "원격보다 앞선 커밋 ${ahead}개 — 직접 push 하거나 정리${waiting}"
        return 1
    fi

    if (( behind == 0 )); then
        # 지난번 make sync 가 실패해 다시 돌릴 차례면 그 실패 표시 (와 시작 시각) 를 그대로 둔다 — runSyncIfPending 이 정리한다
        [[ "${target}" == dotfiles && -f "${SYNC_PENDING}" ]] || setStatus "${target}" latest "최신"
        return 1
    fi

    local before mergeError
    before=$(git -C "${repo}" rev-parse HEAD)

    if ! mergeError=$(git -C "${repo}" merge --ff-only --quiet "origin/${branch}" 2>&1); then
        setStatus "${target}" failed "fast-forward 병합 실패: $(head -n 1 <<<"${mergeError}" | cut -c1-120)"
        return 1
    fi

    PULLED_FROM="${before}"
    log "${target}: ${before:0:12} → $(git -C "${repo}" rev-parse --short=12 HEAD) (되돌리기: git -C ${repo} reset --keep ${before:0:12})"
    setStatus "${target}" updated "받음 ${behind}커밋"
    return 0
}

#--------------------------------------------------------------------------
# 대상 ① dotfiles
#--------------------------------------------------------------------------

# 이 스크립트 (~/.local/bin 의 링크) 가 가리키는 저장소 — dotfiles 를 ~/.dotfiles 밖에 둔 장비도 맞게
findDotfiles() {
    local scriptPath="${BASH_SOURCE[0]}"

    if [[ -L "${scriptPath}" ]]; then
        scriptPath=$(readlink "${scriptPath}")
    fi

    (cd "$(dirname "${scriptPath}")/.." && pwd)
}

# 인자: dotfiles, 받기 전 커밋. 받은 범위에서 사람이 볼 변경을 적는다
noteDotfilesChanges() {
    local dotfiles=$1
    local before=$2
    local changed
    changed=$(git -C "${dotfiles}" diff --name-only "${before}" HEAD)

    if grep -qE '^Brewfile' <<<"${changed}"; then
        setStatus brewfile manual "Brewfile 이 바뀜 — make update 로 패키지 설치"
    fi

    if grep -qxF "launchd/com.socoolbear.dotfiles-auto-update.plist" <<<"${changed}"; then
        log "dotfiles: 이 작업의 예약 설정이 바뀜 — 실행 중에는 다시 걸 수 없어 다음 make sync (손으로) 때 반영"
    fi
}

# 인자: dotfiles. 받은 뒤 새 판으로 다시 시작한다 (exec 는 돌아오지 않는다). 새 판이 없어졌으면 지금 판으로 이어 간다
updateDotfiles() {
    local dotfiles=$1

    if ! updateRepo dotfiles "${dotfiles}"; then
        return 0
    fi

    touch "${SYNC_PENDING}"
    noteDotfilesChanges "${dotfiles}" "${PULLED_FROM}"

    local newScript="${dotfiles}/scripts/dotfiles-auto-update.sh"

    if [[ -f "${newScript}" ]]; then
        log "dotfiles: 새 판으로 다시 시작"
        DOTFILES_AUTO_UPDATE_STAGE=after-dotfiles exec /bin/bash "${newScript}"
    fi

    log "dotfiles: 새 판 스크립트가 없어 지금 판으로 이어 감"
}

# 인자: dotfiles. 받은 뒤 (또는 지난번에 실패한 뒤) make sync 를 돌린다
runSyncIfPending() {
    local dotfiles=$1

    [[ -f "${SYNC_PENDING}" ]] || return 0

    log "==> make sync"

    if DOTFILES_AUTO_UPDATE_RUNNING=1 make -C "${dotfiles}" sync >>"${LOG}" 2>&1; then
        rm -f "${SYNC_PENDING}"
        log "make sync: 성공"

        # 이번에 받은 경우 (updated) 가 아니면 다시 돌린 것이다 — 남아 있던 실패 표시를 최신으로 바꾼다
        if ! grep -q $'^dotfiles\tupdated\t' "${STATUS}" 2>/dev/null; then
            setStatus dotfiles latest "최신 (지난번에 실패한 make sync 를 다시 돌려 성공)"
        fi

        return 0
    fi

    setStatus dotfiles failed "받았지만 make sync 실패 — 로그 확인 뒤 make sync (다음 실행 때 다시 시도)"
}

# 인자: dotfiles. Brewfile 표시가 있으면, 패키지가 모두 깔렸는지 (네트워크 없이) 다시 보고 깔렸으면 지운다
recheckBrewfile() {
    local dotfiles=$1

    [[ -f "${STATUS}" ]] && grep -q $'^brewfile\tmanual\t' "${STATUS}" || return 0
    command -v brew >/dev/null 2>&1 || return 0

    if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="${dotfiles}/Brewfile" >/dev/null 2>&1; then
        writeStatusLine brewfile ""
        log "brewfile: 패키지가 모두 깔림 — 표시 지움"
    fi
}

#--------------------------------------------------------------------------
# 대상 ② cc-marketplace 체크아웃 — 규칙 폴더 ~/.claude/workstyle 이 체크아웃을 가리키는 심링크일 때만
#--------------------------------------------------------------------------

updateMarketplaceCheckout() {
    local rulesLink="${HOME}/.claude/workstyle"
    local root=""

    if [[ -L "${rulesLink}" ]]; then
        root=$(git -C "$(readlink "${rulesLink}")" rev-parse --show-toplevel 2>/dev/null || true)
    fi

    if [[ -z "${root}" ]]; then
        setStatus cc-marketplace skipped "체크아웃 없음"
        return 0
    fi

    updateRepo cc-marketplace "${root}" || true
}

#--------------------------------------------------------------------------
# 대상 ③ 설치된 Claude 플러그인 — 세션 시작 때의 자동 갱신과 같은 범위
#   autoUpdate 가 켜진 마켓플레이스 (값이 없으면 공식 마켓플레이스만 켜진 것으로 본다 — Claude Code 기본값) 를 갱신하고,
#   그 마켓플레이스에서 켜 둔 플러그인을 갱신한다. 플러그인이 새 명령 승인을 요구하면 -y 로 넘기지 않고 손 필요로 둔다.
#--------------------------------------------------------------------------

listAutoUpdateMarketplaces() {
    jq -r 'to_entries[] | select(.value.autoUpdate == true or (.value.autoUpdate == null and .key == "claude-plugins-official")) | .key' \
        "${HOME}/.claude/plugins/known_marketplaces.json"
}

# 인자: 마켓플레이스 이름 목록 (줄마다)
listEnabledPlugins() {
    jq -r --arg markets "$1" '
        ($markets | split("\n")) as $names
        | .enabledPlugins // {} | to_entries[]
        | select(.value == true and ((.key | split("@") | last) as $m | $names | index($m)))
        | .key' "${HOME}/.claude/settings.json"
}

# claude plugin 명령은 settings.json 을 다시 쓰면서 키 순서를 바꾼다 — 내용이 같으면 원래 글로 되돌려 dotfiles 작업 트리를 지킨다
restoreSettingsIfSame() {
    local backup=$1
    local settings="${HOME}/.claude/settings.json"

    if [[ "$(jq -S . "${backup}" 2>/dev/null)" == "$(jq -S . "${settings}" 2>/dev/null)" ]]; then
        cat "${backup}" >"${settings}"
    fi
}

updatePlugins() {
    if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
        setStatus plugins skipped "claude 명령 없음"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        setStatus plugins failed "명령 없음: jq"
        return 0
    fi

    if [[ ! -f "${HOME}/.claude/plugins/known_marketplaces.json" || ! -f "${HOME}/.claude/settings.json" ]]; then
        setStatus plugins skipped "마켓플레이스 · settings.json 없음"
        return 0
    fi

    local backup
    if ! backup=$(mktemp "${STATE_DIR}/settings.XXXXXX"); then
        setStatus plugins failed "임시 파일을 만들지 못함 (mktemp)"
        return 0
    fi

    cp "${HOME}/.claude/settings.json" "${backup}"

    local markets market
    markets=$(listAutoUpdateMarketplaces)

    while IFS= read -r market; do
        [[ -n "${market}" ]] || continue
        runLimited "${CLAUDE_TIMEOUT_SECONDS}" "${CLAUDE_BIN}" plugin marketplace update "${market}" </dev/null >>"${LOG}" 2>&1 \
            || log "plugins: 마켓플레이스 갱신 실패 — ${market}"
    done <<<"${markets}"

    local updated=() failed=() plugin result outcome
    while IFS= read -r plugin; do
        [[ -n "${plugin}" ]] || continue

        if ! result=$(runLimited "${CLAUDE_TIMEOUT_SECONDS}" "${CLAUDE_BIN}" plugin update "${plugin}" --json </dev/null 2>>"${LOG}"); then
            failed+=("${plugin%@*}")
            log "plugins: ${plugin} 갱신 실패 — $(tail -n 1 <<<"${result}" | cut -c1-200)"
            continue
        fi

        outcome=$(tail -n 1 <<<"${result}" | jq -r '.updateOutcome // empty' 2>/dev/null || true)

        if [[ "${outcome}" != "up_to_date" ]]; then
            updated+=("${plugin%@*}")
            log "plugins: ${plugin} — $(tail -n 1 <<<"${result}" | jq -r '.message // empty' 2>/dev/null || true)"
        fi
    done < <(listEnabledPlugins "${markets}")

    restoreSettingsIfSame "${backup}"
    rm -f "${backup}"

    if (( ${#failed[@]} > 0 )); then
        setStatus plugins manual "갱신하지 못한 플러그인: ${failed[*]} — 세션에서 /plugin 으로 확인"
    elif (( ${#updated[@]} > 0 )); then
        setStatus plugins updated "받음: ${updated[*]} (Claude 세션을 다시 열면 반영)"
    else
        setStatus plugins latest "최신"
    fi
}

#--------------------------------------------------------------------------

# 메뉴 막대 항목을 바로 다시 그린다 (SwiftBar 가 떠 있을 때만 — 아니면 5분 주기에 맡긴다)
refreshMenuBar() {
    pgrep -xq SwiftBar || return 0
    /usr/bin/open -g "swiftbar://refreshplugin?name=${SWIFTBAR_PLUGIN}" >/dev/null 2>&1 || true
}

# 인자: 명령 이름... — 없는 것을 출력한다
missingCommands() {
    local name

    for name in "$@"; do
        command -v "${name}" >/dev/null 2>&1 || printf '%s ' "${name}"
    done
}

main() {
    mkdir -p "${STATE_DIR}" "$(dirname "${LOG}")"
    export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:${PATH}"

    case "${1:-}" in
        --status)
            printStatus
            return 0
            ;;
        --dismiss)
            writeStatusLine "${2:?지울 대상 이름}" ""
            refreshMenuBar
            return 0
            ;;
    esac

    if ! acquireLock; then
        log "이미 실행 중 — 건너뜀"
        echo "이미 실행 중입니다."
        return 0
    fi

    trap releaseLock EXIT

    local stage="${DOTFILES_AUTO_UPDATE_STAGE:-}"
    unset DOTFILES_AUTO_UPDATE_STAGE

    if [[ -z "${stage}" ]]; then
        rotateLog
        log "===== 시작 ====="
        # 갱신이 끝날 때까지 맥이 잠들지 않게 한다 (exec 뒤에도 pid 가 같아 계속 지켜진다)
        /usr/bin/caffeinate -i -w $$ &
    fi

    exportUnattendedGit

    local dotfiles missing
    dotfiles=$(findDotfiles)
    # shellcheck disable=SC2086 # 명령 이름 목록을 인자로 나눈다
    missing=$(missingCommands ${REQUIRED_COMMANDS})

    if [[ -n "${missing}" ]]; then
        setStatus dotfiles failed "명령 없음: ${missing% }"
        setStatus cc-marketplace failed "명령 없음: ${missing% }"
    else
        [[ -n "${stage}" ]] || updateDotfiles "${dotfiles}"
        runSyncIfPending "${dotfiles}"
        recheckBrewfile "${dotfiles}"
        updateMarketplaceCheckout
    fi

    updatePlugins

    writeStatusLine last_run "last_run"$'\t'"$(date '+%Y-%m-%d %H:%M')"$'\t'"$(date +%s)"
    log "===== 완료 ====="
    refreshMenuBar
    printStatus
}

main "$@"; exit $?
