#!/usr/bin/env bash
#
# dotfiles · cc-marketplace 체크아웃 · Claude 플러그인을 Claude 세션과 별개로 하루 1회 갱신하는 예약 작업
# (launchd: com.socoolbear.dotfiles-auto-update).
#
# 안전할 때만 조용히 받고, 못 받았으면 상태 파일에 "직접 확인 필요" (manual) 로 적는다. 메뉴 막대 (swiftbar/dotfiles-update.5m.sh) 는
# 그 파일의 짧은 메뉴 줄만 띄우고, 상세 (플러그인 이름 · 이유 · 할 일) 는 로그와 메일로 보낸다. 평소에는 아무것도 띄우지 않는다.
#
# 메일 — 확인할 것 (직접 확인 필요 · 실패 · 하루 넘게 받아오지 못함) 이 새로 생겼을 때만 한 통 (scripts/send-mail.sh, 장비 점검과 같은 것).
# 같은 상태가 이어지는 동안은 다시 보내지 않고 (보낸 것은 notified 에 적어 둔다), 상세가 바뀌면 새로 생긴 것으로 본다.
# 풀린 것만으로는 보내지 않는다. 본문에는 스크립트가 분류한 이유만 넣고 명령의 오류 문장은 넣지 않는다 (로그에만).
# 못 보냈으면 실패 표시 파일 (mail-failed) 을 두고 다음 실행 때 다시 보낸다 — 다음 machine.sh 가 그 파일을 WARN 으로 낸다.
# 끄기: DOTFILES_AUTO_UPDATE_MAIL=0
#
# 저장소 (dotfiles · cc-marketplace 체크아웃) 를 받는 조건 — 셋 다 맞을 때만 git merge --ff-only:
#   1. 미커밋 · 미추적 변경이 없다   2. 기본 브랜치에 있다   3. 원격보다 앞선 로컬 커밋이 없다
# 하나라도 어긋나면 작업 트리를 건드리지 않는다 (fetch 만 한다). reset · checkout -- · stash · clean 은 쓰지 않는다.
# 받기 전 커밋은 로그에 남긴다. 되돌리기는 사람이 한다 (git reset --keep <커밋>).
#
# 원격 점검 확인 — 깨진 커밋이 모든 장비로 퍼지지 않게, 받으려는 원격 커밋의 GitHub Actions 결과가 성공일 때만 받는다.
# 인증 없는 API 를 받을 커밋이 있을 때만 대상마다 1회 부른다 (GET /repos/{owner}/{repo}/actions/runs?head_sha=…).
# 예약 실행 (schedule) 은 빼고 workflow 마다 최신 실행을 본다 — 전부 success · skipped · neutral 이면 받고,
# 하나라도 실패면 직접 확인 필요, 도는 중 · 아직 실행 없음 · 확인 못함 (네트워크 · API 한도 · 응답 꼴) 은 받지 않고
# "받아오지 못함" 으로 적는다 (메뉴 막대는 하루 넘게 이어질 때만 띄운다). 그 커밋에 workflow 파일이 없으면 확인 없이 받는다.
# 끄기: DOTFILES_AUTO_UPDATE_CI_GATE=0
#
# dotfiles 를 받으면 make sync 를 돌린다. Brewfile 이 바뀌었으면 설치하지 않고 "make update 필요" 로만 적는다.
#
# 스스로를 갱신하는 스크립트다. dotfiles 를 받은 뒤에는 새 판을 exec 로 다시 불러 나머지 단계를 새 판이 하게 한다
# (DOTFILES_AUTO_UPDATE_STAGE=after-dotfiles). 끝줄은 `main "$@"; exit $?` 한 줄이라, 파일이 바뀌어도 그 뒤를 읽지 않는다.
#
# make sync 는 launchd 작업을 bootout · bootstrap 으로 다시 건다. 실행 중인 작업을 bootout 하면 launchd 가 그 작업을 죽이므로,
# 여기서 부른 make sync 는 DOTFILES_AUTO_UPDATE_RUNNING=1 을 받아 이 작업의 다시 걸기를 건너뛴다 (scripts/launchd-agents.sh).
#
# 무인 실행에서 1Password SSH 에이전트의 승인 창이 뜨지 않도록 GitHub 의 SSH 원격 (git@github.com:) 은 HTTPS 로 바꿔 받는다
# (받기만 하므로 공개 저장소면 인증이 필요 없다). 그래도 SSH 로 남는 원격 (다른 호스트 · ssh 설정의 별칭) 은 받지 않고 직접 확인 필요로 둔다.
#
# 사용:
#   dotfiles-auto-update                  지금 갱신 (make auto-update · 메뉴 막대의 "지금 업데이트" 도 같다)
#   dotfiles-auto-update --status         상태 파일을 사람이 읽기 좋게 출력
#   dotfiles-auto-update --dismiss <대상>  "직접 확인 필요" 표시 하나를 지운다 (Brewfile 표시처럼 사람이 확인하고 넘길 것)
#   dotfiles-auto-update --test-mail      지금 상태로 "(시험)" 메일 한 통 (갱신은 하지 않음, notified · 실패 표시는 건드리지 않음)

set -euo pipefail

readonly STATE_DIR="${HOME}/.local/state/dotfiles-update"
readonly STATUS="${STATE_DIR}/status"
readonly LOCK="${STATE_DIR}/lock"
readonly SYNC_PENDING="${STATE_DIR}/sync-pending"
readonly NOTIFIED="${STATE_DIR}/notified"
readonly MAIL_FAILED_FLAG="${STATE_DIR}/mail-failed"
readonly MAIL_ENABLED="${DOTFILES_AUTO_UPDATE_MAIL:-1}"
# 메뉴 막대와 같은 값 — 깨어난 직후 · 오프라인은 넘기고 하루 넘게 이어진 "받아오지 못함" 만 알린다
readonly UNREACHABLE_GRACE_SECONDS=$((24 * 3600))
readonly LOG="${HOME}/Library/Logs/dotfiles-auto-update.log"
readonly MAX_LOG_BYTES=$((1024 * 1024))
readonly FETCH_TIMEOUT_SECONDS=60
readonly CLAUDE_TIMEOUT_SECONDS=180
readonly SWIFTBAR_PLUGIN="dotfiles-update"
# 실패 경로 시험용으로 바꿀 수 있다 (없는 명령 이름을 넣어 "명령 없음" 을 시험)
readonly CLAUDE_BIN="${DOTFILES_AUTO_UPDATE_CLAUDE:-claude}"
readonly REQUIRED_COMMANDS="${DOTFILES_AUTO_UPDATE_REQUIRE:-git make}"
readonly CI_GATE="${DOTFILES_AUTO_UPDATE_CI_GATE:-1}"
readonly CURL_BIN="${DOTFILES_AUTO_UPDATE_CURL:-curl}"
readonly GITHUB_API_TIMEOUT_SECONDS=20

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
# 상태 파일 — 탭으로 나눈 줄. 대상 줄: <대상> <상태> <상세> <그 상태가 시작된 epoch> <메뉴 줄>
#   메뉴 줄: "<대상의 한국어 이름>: <짧은 상태>" — 메뉴 막대 · 메일 목록에 쓰는 한 줄. 이름 나열 · 할 일은 상세에만 둔다.
#   상세: 메일 · 로그 · --status 에 쓰는 한 줄. 스크립트가 고른 문구만 넣는다 (명령의 오류 문장 · 경로는 로그에만)
#   상태: latest (최신) · updated (받음) · manual (직접 확인 필요) · failed (실패) · skipped (없어서 건너뜀)
#         · unreachable (원격에 닿지 못함 — 깨어난 직후 · 오프라인일 수 있어 메뉴 막대는 하루 넘게 이어질 때만 띄운다)
#   last_run 줄: last_run <시각> <epoch>
#--------------------------------------------------------------------------

# 인자: 대상. 메뉴 줄 · 메일에 쓰는 이름
targetLabel() {
    case "$1" in
        plugins) echo "플러그인" ;;
        brewfile) echo "Brewfile" ;;
        *) echo "$1" ;;   # dotfiles · cc-marketplace 는 저장소 이름 그대로
    esac
}

# 인자: 대상, 상태, 짧은 상태 (메뉴 줄), [상세 — 없으면 짧은 상태]. 같은 상태가 이어지면 시작 시각을 그대로 둔다 (장비 점검이 "N일째" 를 센다)
setStatus() {
    local target=$1
    local state=$2
    local summary=$3
    local detail=${4:-$3}
    local now since=""
    now=$(date +%s)

    if [[ -f "${STATUS}" ]]; then
        since=$(awk -F'\t' -v t="${target}" -v s="${state}" '$1 == t && $2 == s { print $4 }' "${STATUS}")
    fi

    writeStatusLine "${target}" "${target}"$'\t'"${state}"$'\t'"${detail}"$'\t'"${since:-${now}}"$'\t'"$(targetLabel "${target}"): ${summary}"
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

    # 메뉴 줄 (옛 판이 적은 줄은 대상: 상세) 을 쓰고, 상세가 더 있으면 다음 줄에 들여 쓴다.
    # 한글 문자열은 == · != 로 견주지 않는다 — macOS awk 는 로캘 정렬로 견주어 다른 한글을 같다고 본다 (index · length 를 쓴다)
    awk -F'\t' '
        $1 == "last_run" { print "마지막 실행: " $2; next }
        length($5) == 0 { print $1 ": " $3; next }
        { print $5; if (index($5, $3) == 0) print "  " $3 }
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
    [[ "$(cat "${LOCK}/pid" 2>/dev/null || true)" == "$$" ]] || return 0

    rm -rf "${LOCK}"
    refreshMenuBar   # 메뉴 막대의 "갱신 중" 을 바로 거둔다
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

# 인자: 원격 주소. GitHub 원격이면 owner/repo 를 출력한다
githubSlug() {
    local slug

    case "$1" in
        https://github.com/*) slug=${1#https://github.com/} ;;
        git@github.com:*) slug=${1#git@github.com:} ;;
        ssh://git@github.com/*) slug=${1#ssh://git@github.com/} ;;
        *) return 1 ;;
    esac

    slug=${slug%/}
    slug=${slug%.git}
    [[ "${slug}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    echo "${slug}"
}

# 인자: owner/repo, 커밋. 그 커밋의 Actions 실행 결과를 판정해 "<판정>\t<설명>" 한 줄로 출력한다
#   판정: success · failure · pending (도는 중 · 실행 없음) · unknown (확인 못함)
checkVerdict() {
    local slug=$1
    local sha=$2

    command -v "${CURL_BIN}" >/dev/null 2>&1 || { printf 'unknown\t명령 없음: curl\n'; return 0; }
    command -v jq >/dev/null 2>&1 || { printf 'unknown\t명령 없음: jq\n'; return 0; }

    local response
    if ! response=$("${CURL_BIN}" -sS --max-time "${GITHUB_API_TIMEOUT_SECONDS}" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
        -w '\n%{http_code}' "https://api.github.com/repos/${slug}/actions/runs?head_sha=${sha}&per_page=100" 2>&1); then
        log "GitHub API 에 닿지 못함: $(head -n 1 <<<"${response}" | cut -c1-200)"
        printf 'unknown\tGitHub API 에 닿지 못함\n'
        return 0
    fi

    local code=${response##*$'\n'}
    local body=${response%$'\n'*}

    case "${code}" in
        200) ;;
        403 | 429) printf 'unknown\tGitHub API 한도 초과 (HTTP %s)\n' "${code}"; return 0 ;;
        *) printf 'unknown\tGitHub API 응답 HTTP %s\n' "${code}"; return 0 ;;
    esac

    local verdict
    if ! verdict=$(jq -r '
        def passed: .conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral";
        if (.workflow_runs | type) != "array" then "unknown\tGitHub API 응답 꼴이 다름"
        else
            [.workflow_runs[] | select(.event != "schedule")] | group_by(.workflow_id) | map(max_by(.id))
            | if length == 0 then "pending\t아직 점검 실행이 없음"
              elif any(.[]; .status != "completed") then "pending\t점검이 도는 중: \(map(select(.status != "completed") | .name) | join(", "))"
              elif all(.[]; passed) then "success\t\(map(.name) | join(", "))"
              else "failure\t\(map(select(passed | not) | "\(.name) (\(.conclusion))") | join(", "))"
              end
        end' <<<"${body}" 2>/dev/null); then
        verdict=$'unknown\tGitHub API 응답을 읽지 못함'
    fi

    echo "${verdict}"
}

# 인자: 대상, 저장소, 기본 브랜치. 받으려는 원격 커밋의 점검이 받아도 되는 상태면 0, 아니면 상태를 적고 1
remoteChecksPassed() {
    local target=$1
    local repo=$2
    local branch=$3

    if [[ "${CI_GATE}" == 0 ]]; then
        log "${target}: 원격 점검 확인 꺼짐 (DOTFILES_AUTO_UPDATE_CI_GATE=0) — 확인 없이 받음"
        return 0
    fi

    local sha workflows
    sha=$(git -C "${repo}" rev-parse "origin/${branch}")
    workflows=$(git -C "${repo}" ls-tree --name-only "${sha}" .github/workflows/)

    if ! grep -qE '\.ya?ml$' <<<"${workflows}"; then
        log "${target}: 원격 커밋 ${sha:0:12} 에 점검 workflow 없음 — 확인 없이 받음"
        return 0
    fi

    local slug
    if ! slug=$(githubSlug "$(git -C "${repo}" config --get remote.origin.url)"); then
        setStatus "${target}" manual "원격 점검을 확인할 수 없음" "GitHub 가 아닌 원격이라 원격 점검 결과를 확인할 수 없어 받지 않음 — 직접 git pull"
        return 1
    fi

    local verdict detail
    IFS=$'\t' read -r verdict detail < <(checkVerdict "${slug}" "${sha}")

    case "${verdict}" in
        success)
            log "${target}: 원격 커밋 ${sha:0:12} 점검 성공 (${detail})"
            return 0
            ;;
        failure)
            setStatus "${target}" manual "원격 커밋의 점검 실패" "원격 최신 커밋 ${sha:0:12} 의 점검 실패: ${detail} — 고친 커밋을 push 하면 다음 실행 때 받음"
            ;;
        pending)
            setStatus "${target}" unreachable "원격 점검이 끝나지 않음" "원격 커밋 ${sha:0:12} 의 점검을 기다리는 중 (${detail}) — 다음 실행 때 다시 봄"
            ;;
        *)
            setStatus "${target}" unreachable "원격 점검 결과를 확인하지 못함" "원격 커밋 ${sha:0:12} 의 점검 결과를 확인하지 못해 받지 않음 (${detail:-판정 없음})"
            ;;
    esac

    return 1
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
        setStatus "${target}" manual "SSH 원격이라 받지 않음" "SSH 원격은 승인 창이 뜰 수 있어 무인으로 받지 않음 — 직접 git pull 하거나 원격을 HTTPS 로"
        return 1
    fi

    local fetchError
    if ! fetchError=$(runLimited "${FETCH_TIMEOUT_SECONDS}" git -C "${repo}" fetch --quiet origin 2>&1); then
        log "${target}: git fetch 실패 — $(head -n 1 <<<"${fetchError}" | cut -c1-200)"
        setStatus "${target}" unreachable "원격에 닿지 못함" "원격에서 받아오지 못함 — 네트워크 · 원격 주소 확인 (오류 문장은 로그에)"
        return 1
    fi

    local branch current
    if ! branch=$(defaultBranch "${repo}"); then
        setStatus "${target}" failed "기본 브랜치를 찾지 못함" "원격의 기본 브랜치를 찾지 못함 — 그 저장소에서 git remote set-head origin --auto"
        return 1
    fi

    current=$(git -C "${repo}" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(브랜치 아님)")

    local behind ahead
    behind=$(git -C "${repo}" rev-list --count "HEAD..origin/${branch}")
    ahead=$(git -C "${repo}" rev-list --count "origin/${branch}..HEAD")

    # 받을 커밋 수는 날마다 바뀌어 상세 (메일을 다시 보낼지 가르는 기준) 에 넣지 않고 로그에만 남긴다
    (( behind == 0 )) || log "${target}: 받을 커밋 ${behind}개"

    if [[ -n "$(git -C "${repo}" status --porcelain 2>/dev/null)" ]]; then
        setStatus "${target}" manual "미커밋 변경 있음" "미커밋 · 미추적 변경이 있어 받지 않음 — 그 저장소에서 직접 정리"
        return 1
    fi

    if [[ "${current}" != "${branch}" ]]; then
        log "${target}: 지금 브랜치 ${current}"
        setStatus "${target}" manual "기본 브랜치가 아님" "기본 브랜치 (${branch}) 가 아닌 브랜치에 있어 받지 않음 — 직접 전환하거나 정리"
        return 1
    fi

    if (( ahead > 0 )); then
        setStatus "${target}" manual "push 안 한 커밋 있음" "원격보다 앞선 로컬 커밋 ${ahead}개가 있어 받지 않음 — 직접 push 하거나 정리"
        return 1
    fi

    if (( behind == 0 )); then
        # 지난번 make sync 가 실패해 다시 돌릴 차례면 그 실패 표시 (와 시작 시각) 를 그대로 둔다 — runSyncIfPending 이 정리한다
        [[ "${target}" == dotfiles && -f "${SYNC_PENDING}" ]] || setStatus "${target}" latest "최신"
        return 1
    fi

    if ! remoteChecksPassed "${target}" "${repo}" "${branch}"; then
        return 1
    fi

    local before mergeError
    before=$(git -C "${repo}" rev-parse HEAD)

    if ! mergeError=$(git -C "${repo}" merge --ff-only --quiet "origin/${branch}" 2>&1); then
        log "${target}: git merge --ff-only 실패 — $(head -n 1 <<<"${mergeError}" | cut -c1-200)"
        setStatus "${target}" failed "병합 실패" "fast-forward 병합 실패 — 로그 확인 (make auto-update-log)"
        return 1
    fi

    PULLED_FROM="${before}"
    log "${target}: ${before:0:12} → $(git -C "${repo}" rev-parse --short=12 HEAD) (되돌리기: git -C ${repo} reset --keep ${before:0:12})"
    setStatus "${target}" updated "받음 ${behind}개 커밋"
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
        setStatus brewfile manual "새 패키지 설치 필요" "Brewfile 이 바뀜 — make update 로 패키지 설치 (설치했거나 넘기려면 메뉴의 \"확인함\")"
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
            setStatus dotfiles latest "최신" "최신 (지난번에 실패한 make sync 를 다시 돌려 성공)"
        fi

        return 0
    fi

    setStatus dotfiles failed "make sync 실패" "받았지만 make sync 실패 — 로그 확인 뒤 make sync (다음 실행 때 다시 시도)"
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
#   그 마켓플레이스에서 켜 둔 플러그인을 갱신한다. 플러그인이 새 명령 승인을 요구하면 -y 로 넘기지 않고 직접 확인 필요로 둔다.
#   실패는 --json 결과의 failureCode 로 나눈다. 켜져 있지만 설치되지 않은 것 (not_installed) 은 갱신 실패가 아니라
#   "설치 안 됨" 으로 따로 센다 — 설치는 make sync (scripts/claude-plugins-sync.sh) 의 몫이라 여기서 하지 않는다
#   (무인 실행이 새 플러그인의 훅 · 명령을 들이지 않게).
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

# 인자: claude 종료 코드, --json 결과 줄. 실패 이유를 출력한다 — not_installed 또는 사람이 읽는 짧은 이유.
# 명령의 오류 문장 (message) 은 쓰지 않는다 (메일에 들어간다). failureCode 는 Claude Code 의 고정 식별자라 그대로 써도 된다
pluginFailureReason() {
    local exitCode=$1
    local result=$2
    local code

    if (( exitCode == 124 || exitCode == 142 )); then
        echo "시간 초과 ${CLAUDE_TIMEOUT_SECONDS}초"
        return 0
    fi

    code=$(jq -r 'if .shownCommand then "command_shown" else (.failureCode // empty) end' <<<"${result}" 2>/dev/null || true)

    case "${code}" in
        not_installed | not_installed_at_scope) echo "not_installed" ;;
        command_shown | command_source_refused) echo "새 명령 승인 필요, 세션의 /plugin 에서 갱신" ;;
        *)
            if [[ "${code}" =~ ^[a-z_]{1,60}$ ]]; then
                echo "${code}"
            else
                echo "알 수 없는 오류, exit ${exitCode}"
            fi
            ;;
    esac
}

# 인자: 구분자, 값... — 값들을 구분자로 잇는다
joinBy() {
    local separator=$1
    local joined=$2
    shift 2

    local value
    for value in "$@"; do
        joined+="${separator}${value}"
    done

    echo "${joined}"
}

updatePlugins() {
    if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
        setStatus plugins skipped "claude 명령 없음"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        setStatus plugins failed "jq 명령 없음"
        return 0
    fi

    if [[ ! -f "${HOME}/.claude/plugins/known_marketplaces.json" || ! -f "${HOME}/.claude/settings.json" ]]; then
        setStatus plugins skipped "설정 파일 없음" "마켓플레이스 목록 · settings.json 없음"
        return 0
    fi

    local backup
    if ! backup=$(mktemp "${STATE_DIR}/settings.XXXXXX"); then
        setStatus plugins failed "임시 파일을 만들지 못함" "임시 파일을 만들지 못함 (mktemp)"
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

    local updated=() failed=() notInstalled=() plugin result exitCode outcome reason
    while IFS= read -r plugin; do
        [[ -n "${plugin}" ]] || continue

        exitCode=0
        result=$(runLimited "${CLAUDE_TIMEOUT_SECONDS}" "${CLAUDE_BIN}" plugin update "${plugin}" --json </dev/null 2>>"${LOG}") || exitCode=$?
        result=$(tail -n 1 <<<"${result}")

        if (( exitCode != 0 )); then
            log "plugins: ${plugin} 갱신 실패 (exit ${exitCode}) — $(cut -c1-300 <<<"${result}")"
            reason=$(pluginFailureReason "${exitCode}" "${result}")

            if [[ "${reason}" == "not_installed" ]]; then
                notInstalled+=("${plugin%@*}")
            else
                failed+=("${plugin%@*} (${reason})")
            fi

            continue
        fi

        outcome=$(jq -r '.updateOutcome // empty' <<<"${result}" 2>/dev/null || true)

        if [[ "${outcome}" != "up_to_date" ]]; then
            updated+=("${plugin%@*}")
            log "plugins: ${plugin} — $(jq -r '.message // empty' <<<"${result}" 2>/dev/null || true)"
        fi
    done < <(listEnabledPlugins "${markets}")

    restoreSettingsIfSame "${backup}"
    rm -f "${backup}"

    local summaries=() details=()

    if (( ${#failed[@]} > 0 )); then
        summaries+=("갱신 실패 ${#failed[@]}개")
        details+=("갱신 실패: $(joinBy ", " "${failed[@]}")")
    fi

    if (( ${#notInstalled[@]} > 0 )); then
        summaries+=("설치 안 됨 ${#notInstalled[@]}개")
        details+=("설치 안 됨 (make sync 로 설치): $(joinBy ", " "${notInstalled[@]}")")
    fi

    if (( ${#summaries[@]} > 0 )); then
        setStatus plugins manual "$(joinBy " · " "${summaries[@]}")" "$(joinBy " / " "${details[@]}")"
    elif (( ${#updated[@]} > 0 )); then
        setStatus plugins updated "받음 ${#updated[@]}개" "받음: $(joinBy ", " "${updated[@]}") (Claude 세션을 다시 열면 반영)"
    else
        setStatus plugins latest "최신"
    fi
}

#--------------------------------------------------------------------------
# 메일 — 확인할 것이 새로 생겼을 때만 한 통
#--------------------------------------------------------------------------

# 확인할 것 (메뉴 막대가 띄우는 것과 같은 기준) 을 "<키>\t<메뉴 줄>\t<상세>" 로 출력한다.
# 키 = 대상 · 상태 · 상세 — 상세가 바뀌면 (실패한 플러그인이 달라짐 · 새 원격 커밋의 점검 실패) 새로 생긴 것으로 본다
listAttention() {
    [[ -f "${STATUS}" ]] || return 0

    awk -F'\t' -v now="$(date +%s)" -v grace="${UNREACHABLE_GRACE_SECONDS}" '
        $1 == "last_run" { next }
        $2 == "manual" || $2 == "failed" || ($2 == "unreachable" && now - $4 > grace) {
            line = (length($5) > 0 ? $5 : $1 ": " $3)
            if ($2 == "unreachable") line = line " (하루 넘게)"
            print $1 "|" $2 "|" $3 "\t" line "\t" $3
        }' "${STATUS}"
}

machineName() {
    scutil --get LocalHostName 2>/dev/null || hostname -s
}

# 인자: 확인할 것 (listAttention 출력). 상태 파일의 메뉴 줄 · 상세 (스크립트가 고른 문구) 와 고정 안내만 쓴다
buildMailBody() {
    printf '%s 의 dotfiles 자동 갱신에 확인할 것이 있습니다 (%s).\n\n' "$(machineName)" "$(date '+%Y-%m-%d %H:%M')"
    awk -F'\t' '{ print "- " $2; if (index($2, $3) == 0) print "  " $3 }' <<<"$1"
    printf '%s\n' "" \
        "할 일" \
        "- 상태와 최근 로그: make auto-update-log" \
        "- 정리한 뒤 다시 받기: make auto-update (메뉴 막대의 \"지금 업데이트\" 와 같음)" \
        "- 플러그인 설치 · make sync 실패: make sync" \
        "" \
        "같은 상태가 이어지는 동안은 다시 보내지 않습니다."
}

# 인자: 저장소, 제목, 본문. 장비 점검과 함께 쓰는 scripts/send-mail.sh 로 보낸다. 못 보냈으면 이유를 출력하고 1
sendMail() {
    local mailScript="$1/scripts/send-mail.sh"

    [[ -f "${mailScript}" ]] || { echo "메일 스크립트 없음 (scripts/send-mail.sh)"; return 1; }
    SEND_MAIL_CLAUDE="${CLAUDE_BIN}" bash "${mailScript}" "$2" <<<"$3"
}

# 인자: 저장소. 보낸 적 없는 확인할 것이 생겼으면 메일 한 통. 보낸 것은 NOTIFIED 에 적고, 풀린 것은 거기서 지운다
notifyIfNew() {
    local dotfiles=$1
    local items keys
    items=$(listAttention)
    keys=$(cut -f1 <<<"${items}" | sed '/^$/d')

    if [[ -z "${keys}" ]]; then
        rm -f "${NOTIFIED}"
        return 0
    fi

    local newKeys=${keys} keptKeys=""
    if [[ -f "${NOTIFIED}" ]]; then
        newKeys=$(grep -vxF -f "${NOTIFIED}" <<<"${keys}" || true)
        keptKeys=$(grep -xF -f "${NOTIFIED}" <<<"${keys}" || true)
    fi

    if [[ -z "${newKeys}" ]]; then
        printf '%s\n' "${keys}" >"${NOTIFIED}"
        return 0
    fi

    if [[ "${MAIL_ENABLED}" == 0 ]]; then
        log "메일: 보내지 않음 (DOTFILES_AUTO_UPDATE_MAIL=0)"
        return 0
    fi

    local count subject reason
    count=$(grep -c . <<<"${keys}")
    subject="dotfiles 자동 갱신: 확인할 것 ${count}건 ($(machineName))"

    if reason=$(sendMail "${dotfiles}" "${subject}" "$(buildMailBody "${items}")"); then
        printf '%s\n' "${keys}" >"${NOTIFIED}"
        rm -f "${MAIL_FAILED_FLAG}"
        log "메일: 보냄 (확인할 것 ${count}건, 새로 생긴 것 $(grep -c . <<<"${newKeys}")건)"
        return 0
    fi

    # 새로 생긴 것은 보낸 것으로 적지 않는다 — 다음 실행 때 다시 보낸다
    printf '%s\n' "${keptKeys}" | sed '/^$/d' >"${NOTIFIED}"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "${reason}" >"${MAIL_FAILED_FLAG}"
    log "메일: 실패 (${reason}) — 다음 실행 때 다시 보냄"
}

# 지금 상태로 "(시험)" 메일 한 통. 확인할 것이 없으면 예시 줄을 넣는다. NOTIFIED · 실패 표시는 건드리지 않는다
sendTestMail() {
    local items reason
    items=$(listAttention)
    [[ -n "${items}" ]] || items=$'예시\t(시험) 예시 줄 — 지금은 확인할 것이 없음\t실제 메일에는 대상별 상세와 이유가 들어갑니다'

    if reason=$(sendMail "$(findDotfiles)" "dotfiles 자동 갱신 (시험) — $(machineName)" "$(buildMailBody "${items}")"); then
        log "메일 시험: 보냄"
        echo "시험 메일을 보냈습니다 (갱신은 하지 않음)."
    else
        log "메일 시험: 실패 (${reason})"
        echo "시험 메일을 보내지 못했습니다: ${reason}"
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
        --test-mail)
            sendTestMail
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
        refreshMenuBar   # 메뉴 막대에 "갱신 중" 을 바로 띄운다
        # 갱신이 끝날 때까지 맥이 잠들지 않게 한다 (exec 뒤에도 pid 가 같아 계속 지켜진다)
        /usr/bin/caffeinate -i -w $$ &
    fi

    exportUnattendedGit

    local dotfiles missing
    dotfiles=$(findDotfiles)
    # shellcheck disable=SC2086 # 명령 이름 목록을 인자로 나눈다
    missing=$(missingCommands ${REQUIRED_COMMANDS})

    if [[ -n "${missing}" ]]; then
        setStatus dotfiles failed "${missing% } 명령 없음"
        setStatus cc-marketplace failed "${missing% } 명령 없음"
    else
        [[ -n "${stage}" ]] || updateDotfiles "${dotfiles}"
        runSyncIfPending "${dotfiles}"
        recheckBrewfile "${dotfiles}"
        updateMarketplaceCheckout
    fi

    updatePlugins

    writeStatusLine last_run "last_run"$'\t'"$(date '+%Y-%m-%d %H:%M')"$'\t'"$(date +%s)"
    refreshMenuBar
    notifyIfNew "${dotfiles}"
    log "===== 완료 ====="
    printStatus
}

main "$@"; exit $?
