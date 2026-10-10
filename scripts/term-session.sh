#!/usr/bin/env bash
#
# 터미널 작업 환경 저장·복원 — Ghostty 창·탭 / tmux 세션·탭·pane / pane 안의 claude.
# ~/.local/bin/term-session 으로 링크된다.
#
# pane 상태를 레코드 (JSON 1개) 로 읽고, 같은 레코드로 pane 을 다시 띄운다.
#   claude pane   {"cwd": …, "claude": {"sessionId", "name", "args", "env", "status", "transcript"}}
#   다른 프로그램 {"cwd": …, "command": "npm run dev"}
#   빈 셸        {"cwd": …}
#
# claude 세션 ID 는 실행 중인 claude 가 쓰는 ~/.claude/sessions/<pid>.json 에서 읽는다.
# 공식 문서에 없는 파일이고 프로세스가 끝나면 지워지므로, 저장은 claude 가 살아 있을 때 해야 한다.
#
# 다시 띄우기 = respawn-pane -k (새 zsh, 새 설정 반영) + send-keys 로 명령 입력.
# claude 는 `claude <원래 옵션> --resume <id>` 를 입력하고 Enter 까지 친다 (--no-enter 면 입력만).
# 다른 프로그램은 자동 재실행이 위험하므로 항상 입력만 해 둔다.
#
# 세션 기록 = 이름 + tmux 탭 (window) 목록. 탭마다 이름·#{window_layout}·pane 레코드 목록을 담는다.
# 복원은 탭마다 pane 을 같은 수만큼 나눈 뒤 select-layout 으로 배치를 되살리고 pane 마다 1단계를 반복한다.
# 제자리 재시작은 claude pane 과 빈 셸 pane 만 다시 띄운다 (다른 프로그램 pane 은 건드리지 않음).
#
# 전체 기록 (save) = Ghostty 창·탭 목록 + tmux 세션 기록 전부, 파일 하나 (~/.local/state/term-session/snapshot.json).
# restore 는 사라진 층만 되살린다 — 살아 있는 tmux 세션은 다시 붙이기만, 이미 Ghostty 탭에 떠 있는 세션은 건너뜀.
# claude 안의 백그라운드 명령·cron·/loop 는 resume 해도 돌아오지 않으므로 save 때와 restore 뒤에 목록으로 알린다.
#
# 사용법:
#   term-session save    [-o <file>]                 # 끄기 전에 (claude 가 살아 있을 때)
#   term-session restore [<file>] [--no-enter] [--dry-run]   # 재부팅·Ghostty 재시작 뒤 (--dry-run 은 할 일만 출력)
#   term-session restart [--force] [--no-enter]      # Claude 버전업·zsh 설정 반영 (모든 세션 제자리 재시작)
#
#   term-session pane-save    [<pane>]                         # 레코드를 stdout 으로
#   term-session pane-restore <pane> <file|-> [--force] [--no-enter]
#   term-session pane-restart [<pane>] [--force] [--no-enter]  # 제자리 재시작 (save + restore)
#
#   term-session session-save    [<session>] [-o <file>]        # 기본 파일: ~/.local/state/term-session/<session>.json
#   term-session session-restore <file> [--no-enter]           # 같은 이름의 세션이 있으면 거부
#   term-session session-restart [<session>] [--force] [--no-enter]
#
# <pane> 은 tmux target (예: %3), <session> 은 세션 이름. 생략하면 현재 pane / 세션.
# TERM_SESSION_TMUX_SOCKET 를 주면 그 이름의 tmux 서버 (tmux -L) 를 쓴다 (시험용).

set -euo pipefail

readonly SESSIONS_DIR="${HOME}/.claude/sessions"
readonly PROJECTS_DIR="${HOME}/.claude/projects"
readonly TAB=$'\t'
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/term-session"

tm() {
    if [[ -n "${TERM_SESSION_TMUX_SOCKET:-}" ]]; then
        tmux -L "${TERM_SESSION_TMUX_SOCKET}" "$@"
        return
    fi

    tmux "$@"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARN: $*" >&2
}

resolvePane() {
    local pane=${1:-${TMUX_PANE:-}}

    [[ -n "${pane}" ]] || die "pane 을 지정하세요 (tmux 밖에서 실행 중)"
    tm display-message -p -t "${pane}" '#{pane_id}' 2>/dev/null || die "pane 을 찾을 수 없음 — ${pane}"
}

# 셸의 자손 pid 를 너비 우선으로 출력한다.
# pgrep -P 는 자기 조상을 결과에서 빼므로 (claude 안에서 실행하면 그 claude 를 놓침) ps 를 쓴다.
listDescendants() {
    local rootPid=$1

    ps -ax -o pid=,ppid= | awk -v root="${rootPid}" '
        { children[$2] = children[$2] " " $1 }
        END {
            queue[1] = root; head = 1; tail = 1
            while (head <= tail) {
                n = split(children[queue[head++]], kids, " ")
                for (i = 1; i <= n; i++) { print kids[i]; queue[++tail] = kids[i] }
            }
        }'
}

findClaudePid() {
    local shellPid=$1
    local pid

    for pid in $(listDescendants "${shellPid}"); do
        if [[ "$(basename "$(ps -o comm= -p "${pid}" 2>/dev/null)")" == "claude" ]]; then
            echo "${pid}"
            return
        fi
    done
}

# 원래 실행 옵션에서 resume/continue 와 이름 옵션을 뺀다. 이름은 세션 파일 값으로 다시 붙인다 (/rename 반영).
# ps args 는 인자 경계를 잃으므로 공백이 든 인자는 보존되지 않는다 (이름은 세션 파일에서 오므로 안전).
stripClaudeArgs() {
    local skipValue=0
    local arg

    for arg in "$@"; do
        if (( skipValue )); then
            skipValue=0
            [[ "${arg}" == -* ]] || continue
        fi

        case "${arg}" in
            -c|--continue|--resume=*|--name=*) ;;
            -r|--resume|-n|--name) skipValue=1 ;;
            *) printf '%s\n' "${arg}" ;;
        esac
    done
}

listClaudeEnv() {
    local pid=$1

    ps -E -ww -o command= -p "${pid}" | tr ' ' '\n' | grep -E '^CLAUDE_CODE_[A-Z0-9_]+=' | sort || true
}

# 명령 앞에 붙인 CLAUDE_CODE_* 만 뽑는다 (cct 의 AGENT_TEAMS 등).
# 셸에서 물려받은 변수 (세션 ID·토큰 등) 는 새 셸이 다시 갖거나 옮기면 안 되므로 뺀다.
readClaudeEnv() {
    local pid=$1
    local shellPid=$2

    comm -23 <(listClaudeEnv "${pid}") <(listClaudeEnv "${shellPid}")
}

hasTranscript() {
    local sessionId=$1

    compgen -G "${PROJECTS_DIR}/*/${sessionId}.jsonl" >/dev/null
}

listAncestors() {
    local pid=$$

    while (( pid > 1 )); do
        echo "${pid}"
        pid=$(ps -o ppid= -p "${pid}" | tr -d ' ')
    done
}

# claude 의 Bash 도구 명령은 claude 의 자식 셸 (shell-snapshots 를 source) 로 돈다.
# 이 스크립트를 실행 중인 셸 (내 조상) 을 빼면 남는 것이 백그라운드 명령이다.
listBackgroundCommands() {
    local claudePid=$1

    local ancestors
    ancestors=$(listAncestors)

    local pid args
    while read -r pid args; do
        [[ "${args}" == *shell-snapshots* ]] || continue
        grep -qx "${pid}" <<<"${ancestors}" && continue

        args=${args#*"eval '"}
        echo "백그라운드 명령: ${args%%"' < /dev/null"*}" | cut -c1-120
    done < <(ps -ax -ww -o pid=,ppid=,args= | awk -v p="${claudePid}" '$2 == p { $2 = ""; print }')
}

# cron (/loop 고정 주기) 과 ScheduleWakeup (/loop 동적) 은 claude 메모리에만 있어 디스크에 남지 않는다.
# 대화 기록의 도구 호출로 추정한다 — 이 프로세스가 시작된 뒤 만들고 지우지 않은 cron, 마지막이 stop 이 아닌 wakeup.
listScheduledWork() {
    local sessionId=$1
    local startedAtMs=$2

    local transcript
    transcript=$(compgen -G "${PROJECTS_DIR}/*/${sessionId}.jsonl" | head -1)
    [[ -n "${transcript}" ]] || return 0

    jq -rs --argjson started "${startedAtMs}" '
        [.[] | select(.timestamp? and
            ((.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) * 1000 >= $started))] as $recent
        | ([$recent[] | .message.content[]? | select(.type? == "tool_use" and .name == "CronDelete") | .input.id]) as $deleted
        | ([$recent[] | .toolUseResult? | objects | select(.humanSchedule? and (.id as $id | $deleted | index($id) | not))]
            | .[] | "cron \(.id) (\(.humanSchedule), \(if .recurring then "반복" else "1회 — 이미 실행됐을 수 있음" end))"),
          ([$recent[] | .message.content[]? | select(.type? == "tool_use" and .name == "ScheduleWakeup") | .input]
            | last | select(. != null and (.stop != true)) | "/loop (ScheduleWakeup) 진행 중일 수 있음")
    ' "${transcript}"
}

readClaudeRecord() {
    local pid=$1
    local shellPid=$2
    local sessionFile="${SESSIONS_DIR}/${pid}.json"

    if [[ ! -f "${sessionFile}" ]]; then
        warn "!!!!!!!! claude (pid ${pid}) 의 세션 파일이 없음 — ${sessionFile}"
        warn "!!!!!!!! 세션 ID 를 읽지 못해 resume 할 수 없습니다. SessionStart hook 방식으로 교체가 필요합니다."
        return 1
    fi

    local sessionId
    sessionId=$(jq -r '.sessionId // empty' "${sessionFile}")

    if [[ -z "${sessionId}" ]]; then
        warn "!!!!!!!! ${sessionFile} 에 sessionId 가 없음 — 파일 형식이 바뀐 것 같습니다. hook 방식으로 교체가 필요합니다."
        return 1
    fi

    local transcript=false
    hasTranscript "${sessionId}" && transcript=true

    local -a rawArgs
    read -r -a rawArgs <<<"$(ps -o args= -p "${pid}")"

    local args env
    args=$(stripClaudeArgs "${rawArgs[@]:1}" | jq -R . | jq -s .)
    env=$(readClaudeEnv "${pid}" "${shellPid}" | jq -R 'split("=") | {(.[0]): (.[1:] | join("="))}' | jq -s 'add // {}')

    # resume 해도 돌아오지 않는 작업 — 저장할 때와 복원한 뒤에 알린다
    local lost
    lost=$( { listBackgroundCommands "${pid}"
              listScheduledWork "${sessionId}" "$(jq -r '.startedAt // 0' "${sessionFile}")"; } | jq -R . | jq -s -c .)

    jq -c --argjson args "${args}" --argjson env "${env}" --argjson transcript "${transcript}" --argjson lost "${lost}" \
        '{sessionId, name, status, args: $args, env: $env, transcript: $transcript, lost: $lost}' "${sessionFile}"
}

savePane() {
    local pane
    pane=$(resolvePane "${1:-}")

    local shellPid cwd
    shellPid=$(tm display-message -p -t "${pane}" '#{pane_pid}')
    cwd=$(tm display-message -p -t "${pane}" '#{pane_current_path}')

    local claudePid
    claudePid=$(findClaudePid "${shellPid}")

    if [[ -n "${claudePid}" ]]; then
        local claude
        claude=$(readClaudeRecord "${claudePid}" "${shellPid}") || die "pane ${pane} 의 claude 를 저장하지 못함"
        jq -cn --arg cwd "${cwd}" --argjson claude "${claude}" '{cwd: $cwd, claude: $claude}'
        return
    fi

    local childPid
    childPid=$(listDescendants "${shellPid}" | head -1)

    if [[ -n "${childPid}" ]]; then
        jq -cn --arg cwd "${cwd}" --arg command "$(ps -o args= -p "${childPid}")" '{cwd: $cwd, command: $command}'
        return
    fi

    jq -cn --arg cwd "${cwd}" '{cwd: $cwd}'
}

buildClaudeCommand() {
    local record=$1
    local useResume=$2

    local line="" key value arg
    while IFS=$'\t' read -r key value; do
        line+="${key}=$(printf '%q' "${value}") "
    done < <(jq -r '.claude.env // {} | to_entries[] | "\(.key)\t\(.value)"' <<<"${record}")

    line+="claude"

    local name
    name=$(jq -r '.claude.name // empty' <<<"${record}")
    [[ -z "${name}" ]] || line+=" -n $(printf '%q' "${name}")"

    while IFS= read -r arg; do
        line+=" $(printf '%q' "${arg}")"
    done < <(jq -r '.claude.args[]?' <<<"${record}")

    if (( useResume )); then
        line+=" --resume $(jq -r '.claude.sessionId' <<<"${record}")"
    fi

    echo "${line}"
}

# 셸에 자식 프로세스가 없으면 빈 셸이다. 막 연 pane 은 zsh 가 설정을 읽으며 잠깐 띄우는
# 프로세스 (프롬프트용 git 등) 가 있으므로 최대 3초 기다린다.
isPaneIdle() {
    local pane=$1
    local shellPid
    shellPid=$(tm display-message -p -t "${pane}" '#{pane_pid}')

    local _
    for _ in $(seq 10); do
        [[ -n "$(listDescendants "${shellPid}")" ]] || return 0
        sleep 0.3
    done

    return 1
}

# pane 에 입력할 명령 (빈 셸이면 빈 줄)
buildPaneCommand() {
    local record=$1

    if jq -e '.claude' <<<"${record}" >/dev/null; then
        if jq -e '.claude.transcript' <<<"${record}" >/dev/null; then
            buildClaudeCommand "${record}" 1
            return
        fi

        warn "대화 기록이 없어 새 세션으로 띄웁니다 — 들어가서 /catchup $(jq -r '.claude.name // empty' <<<"${record}") 를 실행하세요"
        buildClaudeCommand "${record}" 0
        return
    fi

    jq -r '.command // empty' <<<"${record}"
}

restorePane() {
    local pane=$1
    local record=$2
    local force=$3
    local enter=$4

    local cwd
    cwd=$(jq -r '.cwd' <<<"${record}")
    [[ -d "${cwd}" ]] || die "cwd 가 없어 건너뜀 (worktree 정리됨?) — ${cwd}"

    if (( ! force )); then
        isPaneIdle "${pane}" || die "pane ${pane} 에서 프로그램이 실행 중 — 덮어쓰려면 --force"
    fi

    local line pressEnter=0
    line=$(buildPaneCommand "${record}")
    ! jq -e '.claude' <<<"${record}" >/dev/null || pressEnter=${enter}

    # 한 번의 tmux 호출로 묶는다 — 자기 pane 을 재시작하면 respawn 이 이 스크립트를 죽이지만
    # 명령은 이미 tmux 서버가 받았으므로 send-keys 까지 끝난다.
    local -a cmd=(respawn-pane -k -t "${pane}" -c "${cwd}")
    [[ -z "${line}" ]] || cmd+=(\; send-keys -t "${pane}" -l "${line}")
    (( ! pressEnter )) || cmd+=(\; send-keys -t "${pane}" Enter)

    echo "pane ${pane} ← ${line:-(빈 셸)}" >&2
    tm "${cmd[@]}"
}

resolveSession() {
    local session=$1

    if [[ -z "${session}" ]]; then
        [[ -n "${TMUX_PANE:-}" ]] || die "세션을 지정하세요 (tmux 밖에서 실행 중)"
        session=$(tm display-message -p -t "${TMUX_PANE}" '#S')
    fi

    tm has-session -t "=${session}" 2>/dev/null || die "세션을 찾을 수 없음 — ${session}"
    echo "${session}"
}

saveWindow() {
    local windowId=$1
    local active=$2
    local layout=$3
    local width=$4
    local height=$5
    local name=$6

    local autoRename
    autoRename=$(tm display-message -p -t "${windowId}" '#{automatic-rename}')

    local paneId paneActive record
    local panes=""
    while IFS=${TAB} read -r paneId paneActive; do
        if ! record=$(savePane "${paneId}"); then
            warn "pane ${paneId} 는 cwd 만 저장합니다"
            record=$(jq -cn --arg cwd "$(tm display-message -p -t "${paneId}" '#{pane_current_path}')" \
                '{cwd: $cwd, saveFailed: true}')
        fi

        if [[ "$(jq -r '.claude.status // empty' <<<"${record}")" == "busy" ]]; then
            warn "pane ${paneId} 의 claude 가 작업 중 (busy) — 끄기 전에 끝났는지 확인하세요"
        fi

        panes+=$(jq -c --argjson active "${paneActive}" '. + {active: ($active == 1)}' <<<"${record}")$'\n'
    done < <(tm list-panes -t "${windowId}" -F "#{pane_id}${TAB}#{pane_active}")

    jq -cn --arg name "${name}" --arg layout "${layout}" --argjson active "${active}" \
        --argjson width "${width}" --argjson height "${height}" --arg autoRename "${autoRename}" \
        --argjson panes "$(jq -s . <<<"${panes}")" \
        '{name: $name, autoRename: ($autoRename == "1"), active: ($active == 1),
          layout: $layout, width: $width, height: $height, panes: $panes}'
}

snapshotSession() {
    local session=$1

    local windowId active layout width height name
    local windows=""
    while IFS=${TAB} read -r windowId active layout width height name; do
        windows+=$(saveWindow "${windowId}" "${active}" "${layout}" "${width}" "${height}" "${name}")$'\n'
    done < <(tm list-windows -t "=${session}" \
        -F "#{window_id}${TAB}#{window_active}${TAB}#{window_layout}${TAB}#{window_width}${TAB}#{window_height}${TAB}#{window_name}")

    jq -cn --arg name "${session}" --argjson windows "$(jq -s . <<<"${windows}")" '{name: $name, windows: $windows}'
}

# 직전 기록은 .prev 로 남긴다 (잘못 저장해 덮어써도 한 번은 되돌릴 수 있게).
writeSnapshot() {
    local outFile=$1
    local snapshot=$2

    mkdir -p "$(dirname "${outFile}")"
    jq --arg savedAt "$(date '+%Y-%m-%dT%H:%M:%S%z')" --argjson savedEpoch "$(date +%s)" \
        '. + {savedAt: $savedAt, savedEpoch: $savedEpoch}' <<<"${snapshot}" >"${outFile}.tmp"
    [[ ! -f "${outFile}" ]] || mv "${outFile}" "${outFile%.json}.prev.json"
    mv "${outFile}.tmp" "${outFile}"
}

# 끄면 (또는 resume 해도) 돌아오지 않는 작업 목록. 저장할 때와 복원한 뒤에 같은 목록을 보여 준다.
reportLostWork() {
    local snapshot=$1
    local heading=$2

    local lines
    lines=$(jq -r '[.. | objects | select(.claude?) | .claude | select((.lost // []) | length > 0)]
        | .[] | "  [\(.name // .sessionId[0:8])]", (.lost[] | "    - \(.)")' <<<"${snapshot}")
    [[ -n "${lines}" ]] || return 0

    echo "${heading}" >&2
    echo "${lines}" >&2
}

reportSaved() {
    local outFile=$1

    reportLostWork "$(cat "${outFile}")" "끄기 전 점검 — 아래 작업은 resume 해도 돌아오지 않습니다 (끝났는지 확인하거나 복원 뒤 다시 시작):"
    echo "저장 → ${outFile} (tmux 세션 $(jq '[.. | objects | select(has("windows") and has("name"))] | length' "${outFile}") 개," \
        "pane $(jq '[.. | objects | select(has("cwd"))] | length' "${outFile}") 개," \
        "claude $(jq '[.. | objects | select(has("claude"))] | length' "${outFile}") 개)" >&2

    local failedCount
    failedCount=$(jq '[.. | objects | select(.saveFailed?)] | length' "${outFile}")
    (( failedCount == 0 )) || die "pane ${failedCount} 개의 claude 를 저장하지 못함 (위 경고 참고)"
}

# cwd 가 없으면 (worktree 정리됨) 일단 HOME 에서 pane 을 만든다. 그 pane 은 restorePane 이 건너뛰고 보고한다.
existingDir() {
    local dir=$1

    [[ -d "${dir}" ]] && echo "${dir}" || echo "${HOME}"
}

# windowId 가 비어 있으면 세션에 새 탭을 만든다 (첫 탭은 restoreSession 이 세션과 함께 만든다).
restoreWindow() {
    local session=$1
    local window=$2
    local windowId=$3
    local enter=$4

    if [[ -z "${windowId}" ]]; then
        windowId=$(tm new-window -d -P -F '#{window_id}' -t "=${session}:" \
            -c "$(existingDir "$(jq -r '.panes[0].cwd' <<<"${window}")")")
    fi

    local -a paneIds
    paneIds=("$(tm display-message -p -t "${windowId}" '#{pane_id}')")

    local paneCount index
    paneCount=$(jq '.panes | length' <<<"${window}")
    for (( index = 1; index < paneCount; index++ )); do
        paneIds+=("$(tm split-window -d -P -F '#{pane_id}' -t "${paneIds[index - 1]}" \
            -c "$(existingDir "$(jq -r ".panes[${index}].cwd" <<<"${window}")")")")
    done

    tm select-layout -t "${windowId}" "$(jq -r '.layout' <<<"${window}")" >/dev/null 2>&1 \
        || warn "탭 $(jq -r '.name' <<<"${window}") 의 배치를 되살리지 못함"

    tm rename-window -t "${windowId}" "$(jq -r '.name' <<<"${window}")"
    if jq -e '.autoRename' <<<"${window}" >/dev/null; then
        tm set-window-option -t "${windowId}" automatic-rename on >/dev/null
    fi

    for (( index = 0; index < paneCount; index++ )); do
        ( restorePane "${paneIds[index]}" "$(jq -c ".panes[${index}]" <<<"${window}")" 1 "${enter}" ) \
            || failedCount=$((failedCount + 1))

        if jq -e ".panes[${index}].active" <<<"${window}" >/dev/null; then
            tm select-pane -t "${paneIds[index]}"
        fi
    done

    if jq -e '.active' <<<"${window}" >/dev/null; then
        tm select-window -t "${windowId}"
    fi
}

# 세션을 만들고 실제 이름을 stdout 으로 낸다. name 이 비어 있으면 tmux 가 번호를 붙인다.
restoreSession() {
    local snapshot=$1
    local enter=$2
    local name=$3

    local firstWindow
    firstWindow=$(jq -c '.windows[0]' <<<"${snapshot}")

    local -a nameArgs=()
    [[ -z "${name}" ]] || nameArgs=(-s "${name}")

    local created
    created=$(tm new-session -d -P -F "#{session_name}${TAB}#{window_id}" ${nameArgs[@]+"${nameArgs[@]}"} \
        -x "$(jq -r '.width' <<<"${firstWindow}")" -y "$(jq -r '.height' <<<"${firstWindow}")" \
        -c "$(existingDir "$(jq -r '.panes[0].cwd' <<<"${firstWindow}")")")

    local session=${created%%"${TAB}"*}
    local failedCount=0

    local windowCount index windowId
    windowCount=$(jq '.windows | length' <<<"${snapshot}")
    for (( index = 0; index < windowCount; index++ )); do
        windowId=""
        (( index > 0 )) || windowId=${created#*"${TAB}"}
        restoreWindow "${session}" "$(jq -c ".windows[${index}]" <<<"${snapshot}")" "${windowId}" "${enter}"
    done

    echo "${session}"
    (( failedCount == 0 )) || { warn "세션 ${session}: pane ${failedCount} 개를 되살리지 못함 (위 메시지 참고)"; return 1; }
}

# claude pane 과 빈 셸 pane 을 다시 띄운다. 이 명령을 실행한 pane 은 재시작하면 스크립트가 죽으므로 건드리지 않는다.
restartSession() {
    local session=$1
    local force=$2
    local enter=$3

    local -a paneIds=()
    local paneId
    while IFS= read -r paneId; do
        paneIds+=("${paneId}")
    done < <(tm list-panes -s -t "=${session}" -F '#{pane_id}')

    local record skipped=0
    for paneId in "${paneIds[@]}"; do
        if [[ "${paneId}" == "${TMUX_PANE:-}" ]]; then
            echo "pane ${paneId} 는 이 명령을 실행한 pane 이라 그대로 둠 — 다시 띄우려면: term-session pane-restart --force" >&2
            continue
        fi

        if ! record=$(savePane "${paneId}"); then
            skipped=$((skipped + 1))
            continue
        fi

        if [[ "$(jq -r '.claude.status // empty' <<<"${record}")" == "busy" ]] && (( ! force )); then
            warn "pane ${paneId} 의 claude 가 작업 중 (busy) — 건너뜀 (--force 로 강제)"
            skipped=$((skipped + 1))
            continue
        fi

        if jq -e '.command' <<<"${record}" >/dev/null; then
            echo "pane ${paneId} 는 다른 프로그램 실행 중이라 그대로 둠 — $(jq -r '.command' <<<"${record}")" >&2
            continue
        fi

        ( restorePane "${paneId}" "${record}" 1 "${enter}" ) || skipped=$((skipped + 1))
    done

    (( skipped == 0 )) || die "pane ${skipped} 개를 건너뜀 (위 메시지 참고)"
}

# Ghostty 탭 제목은 tmux set-titles-string 이 정한다 (oh-my-tmux 기본값 "#h ❐ #S ● #I #W").
# 탭과 tmux 세션을 짝지을 단서가 이 제목뿐이라, 형식이 바뀌면 sessionFromTitle 도 고쳐야 한다.
sessionFromTitle() {
    local title=$1

    [[ "${title}" == *"❐ "*" ●"* ]] || return 1
    title=${title#*"❐ "}
    echo "${title%%" ●"*}"
}

# Ghostty 창·탭 목록. 줄마다 "W" (창 시작) 또는 "T<TAB>선택 여부<TAB>터미널 수<TAB>제목".
listGhosttyTabs() {
    osascript <<'APPLESCRIPT'
if application "Ghostty" is not running then return ""
-- tell 블록 안의 tab 은 Ghostty 의 탭 객체라서 탭 문자를 밖에서 정해 둔다
set sep to character id 9
tell application "Ghostty"
    set out to ""
    repeat with w in windows
        set out to out & "W" & linefeed
        repeat with t in tabs of w
            set out to out & "T" & sep & (selected of t) & sep & (count of terminals of t) & sep & (name of t) & linefeed
        end repeat
    end repeat
    return out
end tell
APPLESCRIPT
}

# [{tabs: [{session, selected}]}] — tmux 가 아닌 탭은 빼고 알린다.
snapshotGhostty() {
    local kind selected terminalCount title session
    local windows="" tabs=""

    while IFS=${TAB} read -r kind selected terminalCount title; do
        [[ -n "${kind}" ]] || continue

        if [[ "${kind}" == "W" ]]; then
            [[ -z "${tabs}" ]] || windows+=$(jq -s -c '{tabs: .}' <<<"${tabs}")$'\n'
            tabs=""
            continue
        fi

        if ! session=$(sessionFromTitle "${title}"); then
            warn "tmux 가 아닌 Ghostty 탭은 저장하지 않음 — ${title}"
            continue
        fi

        (( terminalCount == 1 )) || warn "Ghostty 탭을 나눈 칸 (split) 은 저장하지 않음 — 세션 ${session}"
        tabs+=$(jq -cn --arg session "${session}" --argjson selected "${selected}" \
            '{session: $session, selected: $selected}')$'\n'
    done < <(listGhosttyTabs || warn "Ghostty 창 목록을 읽지 못함 (자동화 권한 확인)")

    [[ -z "${tabs}" ]] || windows+=$(jq -s -c '{tabs: .}' <<<"${tabs}")$'\n'
    jq -s -c . <<<"${windows}"
}

saveAll() {
    local outFile=$1

    local session sessions=""
    while IFS= read -r session; do
        sessions+=$(snapshotSession "${session}")$'\n'
    done < <(tm list-sessions -F '#{session_name}')

    writeSnapshot "${outFile}" "$(jq -cn --argjson ghostty "$(snapshotGhostty)" \
        --argjson sessions "$(jq -s . <<<"${sessions}")" '{ghostty: $ghostty, sessions: $sessions}')"
    reportSaved "${outFile}"
}

previewSession() {
    local snapshot=$1

    jq -c '.windows[]' <<<"${snapshot}" | while IFS= read -r window; do
        echo "    탭 $(jq -r '.name' <<<"${window}") (pane $(jq '.panes | length' <<<"${window}") 개)" >&2
        jq -c '.panes[]' <<<"${window}" | while IFS= read -r record; do
            local cwd line
            cwd=$(jq -r '.cwd' <<<"${record}")
            if [[ ! -d "${cwd}" ]]; then
                echo "      ✗ ${cwd} — cwd 가 없어 건너뜀" >&2
                continue
            fi
            line=$(buildPaneCommand "${record}")
            echo "      ${cwd} ← ${line:-(빈 셸)}" >&2
        done
    done
}

# 세션마다 이번 복원에서 쓸 이름을 정한다 (줄마다 "저장 당시 이름<TAB>지금 이름<TAB>ok|partial|reused").
# tmux 서버가 저장 전부터 떠 있고 같은 이름이 있으면 살아 있는 세션이다 (Ghostty 만 재시작한 경우).
# 서버가 저장 뒤에 떴으면 (재부팅) 같은 이름이 있어도 새로 생긴 세션이므로 번호를 새로 받는다.
restoreSessions() {
    local snapshot=$1
    local enter=$2

    local savedEpoch serverStart
    savedEpoch=$(jq -r '.savedEpoch' <<<"${snapshot}")
    serverStart=$(tm display-message -p '#{start_time}' 2>/dev/null || echo 0)

    local count index session name restored
    count=$(jq '.sessions | length' <<<"${snapshot}")
    for (( index = 0; index < count; index++ )); do
        session=$(jq -r ".sessions[${index}].name" <<<"${snapshot}")

        if tm has-session -t "=${session}" 2>/dev/null; then
            if (( serverStart > 0 && serverStart <= savedEpoch )); then
                echo "세션 ${session} 은 살아 있어 그대로 씀" >&2
                printf '%s\t%s\treused\n' "${session}" "${session}"
                continue
            fi
            name=""
        else
            name=${session}
        fi

        if (( dryRun )); then
            echo "세션 ${session} → ${name:-(이름이 겹쳐 새 번호)} 로 새로 만듦" >&2
            previewSession "$(jq -c ".sessions[${index}]" <<<"${snapshot}")"
            printf '%s\t%s\tok\n' "${session}" "${name:-(새 번호)}"
            continue
        fi

        local status=ok
        restored=$(restoreSession "$(jq -c ".sessions[${index}]" <<<"${snapshot}")" "${enter}" "${name}") \
            || status=partial
        echo "세션 ${session} → ${restored} 로 복원" >&2
        printf '%s\t%s\t%s\n' "${session}" "${restored}" "${status}"
    done
}

# 창 하나를 연다. 인자: 선택할 탭 번호, 탭마다 실행할 명령...
openGhosttyWindow() {
    osascript - "$@" <<'APPLESCRIPT' >/dev/null
on run argv
    set selectedIndex to (item 1 of argv) as integer
    tell application "Ghostty"
        set cfg to new surface configuration
        set command of cfg to item 2 of argv
        set w to new window with configuration cfg
        repeat with i from 3 to count of argv
            set cfg to new surface configuration
            set command of cfg to item i of argv
            new tab in w with configuration cfg
        end repeat
        if selectedIndex > 0 then select tab (tab selectedIndex of w)
    end tell
end run
APPLESCRIPT
}

# Ghostty 창·탭을 저장 당시 구성대로 연다. 이미 어느 탭에 떠 있는 세션은 건너뛴다.
restoreGhostty() {
    local snapshot=$1
    local nameMap=$2

    # 탭 제목에 있고 tmux client 도 붙어 있어야 떠 있는 것으로 본다 (연결이 끊긴 채 남은 탭은 제목만 남는다).
    local shown title kind
    shown=$(comm -12 \
        <(listGhosttyTabs | while IFS=${TAB} read -r kind _ _ title; do
            [[ "${kind}" == "T" ]] && sessionFromTitle "${title}"
        done | sort -u) \
        <(tm list-clients -F '#{session_name}' | sort -u) || true)

    local tmuxBin
    tmuxBin=$(command -v tmux)
    [[ -z "${TERM_SESSION_TMUX_SOCKET:-}" ]] || tmuxBin+=" -L ${TERM_SESSION_TMUX_SOCKET}"

    local windowCount windowIndex tabCount tabIndex session current
    windowCount=$(jq '.ghostty | length' <<<"${snapshot}")
    for (( windowIndex = 0; windowIndex < windowCount; windowIndex++ )); do
        local -a commands=()
        local selectedIndex=0
        tabCount=$(jq ".ghostty[${windowIndex}].tabs | length" <<<"${snapshot}")

        for (( tabIndex = 0; tabIndex < tabCount; tabIndex++ )); do
            session=$(jq -r ".ghostty[${windowIndex}].tabs[${tabIndex}].session" <<<"${snapshot}")
            current=$(awk -F '\t' -v s="${session}" '$1 == s { print $2 }' <<<"${nameMap}")

            if [[ -z "${current}" ]]; then
                warn "세션 ${session} 이 복원되지 않아 Ghostty 탭을 열지 않음"
                continue
            fi
            if grep -qxF "${current}" <<<"${shown}"; then
                echo "세션 ${current} 은 이미 Ghostty 탭에 떠 있어 건너뜀" >&2
                continue
            fi

            commands+=("${tmuxBin} attach-session -t =${current}")
            if jq -e ".ghostty[${windowIndex}].tabs[${tabIndex}].selected" <<<"${snapshot}" >/dev/null; then
                selectedIndex=${#commands[@]}
            fi
        done

        (( ${#commands[@]} > 0 )) || continue
        echo "Ghostty 창 열기 — 탭 ${#commands[@]} 개" >&2
        if (( dryRun )); then
            printf '    %s\n' "${commands[@]}" >&2
            continue
        fi
        openGhosttyWindow "${selectedIndex}" "${commands[@]}" || warn "Ghostty 창을 열지 못함 (자동화 권한 확인)"
    done
}

restoreAll() {
    local file=$1
    local enter=$2
    dryRun=$3

    [[ -f "${file}" ]] || die "저장 파일이 없음 — ${file}"

    local snapshot nameMap
    snapshot=$(cat "${file}")
    echo "복원 ← ${file} ($(jq -r '.savedAt' <<<"${snapshot}") 저장)" >&2

    (( ! dryRun )) || echo "(미리보기 — 아무것도 만들지 않음)" >&2
    nameMap=$(restoreSessions "${snapshot}" "${enter}")
    restoreGhostty "${snapshot}" "${nameMap}"
    # 새로 만든 세션의 claude 만 알린다 — 살아 있던 세션은 작업도 그대로 돌고 있다
    local recreated
    recreated=$(awk -F '\t' '$3 != "reused" { print $1 }' <<<"${nameMap}" | jq -R . | jq -s -c .)
    reportLostWork "$(jq -c --argjson names "${recreated}" '.sessions |= map(select(.name as $n | $names | index($n)))' <<<"${snapshot}")" \
        "저장할 때 돌던 아래 작업은 돌아오지 않습니다 (필요하면 다시 시작):"

    local failedCount
    failedCount=$(awk -F '\t' '$3 == "partial"' <<<"${nameMap}" | wc -l | tr -d ' ')
    (( failedCount == 0 )) || die "세션 ${failedCount} 개가 일부만 복원됨 (위 메시지 참고)"
}

restartAll() {
    local force=$1
    local enter=$2

    local session failed=0
    while IFS= read -r session; do
        ( restartSession "${session}" "${force}" "${enter}" ) || failed=$((failed + 1))
    done < <(tm list-sessions -F '#{session_name}')

    (( failed == 0 )) || die "세션 ${failed} 개에서 건너뛴 pane 이 있음 (위 메시지 참고)"
}

parseRestoreFlags() {
    force=0
    enter=1
    dryRun=0

    local flag
    for flag in "$@"; do
        case "${flag}" in
            --force) force=1 ;;
            --no-enter) enter=0 ;;
            --dry-run) dryRun=1 ;;
            *) die "알 수 없는 옵션 — ${flag}" ;;
        esac
    done

    (( ! dryRun )) || [[ "${subcommand}" == restore ]] || die "--dry-run 은 restore 에서만 쓸 수 있습니다"
}

main() {
    subcommand=${1:-}
    shift || true

    local force enter dryRun pane record session outFile
    local snapshotFile="${STATE_DIR}/snapshot.json"

    case "${subcommand}" in
        save)
            [[ "${1:-}" != -o ]] || snapshotFile=${2:?"-o 뒤에 파일 경로가 필요합니다"}
            saveAll "${snapshotFile}"
            ;;
        restore)
            [[ -z "${1:-}" || "${1}" == --* ]] || { snapshotFile=$1; shift; }
            parseRestoreFlags "$@"
            restoreAll "${snapshotFile}" "${enter}" "${dryRun}"
            ;;
        restart)
            parseRestoreFlags "$@"
            restartAll "${force}" "${enter}"
            ;;
        pane-save)
            savePane "${1:-}"
            ;;
        pane-restore)
            (( $# >= 2 )) || die "사용법: term-session pane-restore <pane> <file|-> [--force] [--no-enter]"
            pane=$(resolvePane "$1")
            record=$(cat "$2")
            shift 2
            parseRestoreFlags "$@"
            restorePane "${pane}" "${record}" "${force}" "${enter}"
            ;;
        pane-restart)
            pane=""
            [[ "${1:-}" == --* ]] || { pane=${1:-}; shift || true; }
            pane=$(resolvePane "${pane}")
            parseRestoreFlags "$@"
            record=$(savePane "${pane}")

            if [[ "$(jq -r '.claude.status // empty' <<<"${record}")" == "busy" ]] && (( ! force )); then
                die "pane ${pane} 의 claude 가 작업 중 (busy) — 그래도 재시작하려면 --force"
            fi

            restorePane "${pane}" "${record}" 1 "${enter}"
            ;;
        session-save)
            session=""
            [[ "${1:-}" == -o ]] || { session=${1:-}; shift || true; }
            session=$(resolveSession "${session}")
            outFile="${STATE_DIR}/${session}.json"
            if [[ "${1:-}" == -o ]]; then
                outFile=${2:?"-o 뒤에 파일 경로가 필요합니다"}
            fi
            writeSnapshot "${outFile}" "$(snapshotSession "${session}")"
            reportSaved "${outFile}"
            ;;
        session-restore)
            (( $# >= 1 )) || die "사용법: term-session session-restore <file> [--no-enter]"
            record=$(cat "$1")
            session=$(jq -r '.name' <<<"${record}")
            shift
            parseRestoreFlags "$@"
            ! tm has-session -t "=${session}" 2>/dev/null || die "세션 ${session} 이 이미 떠 있어 건너뜀 (중복 방지)"
            restoreSession "${record}" "${enter}" "${session}" >/dev/null
            echo "세션 ${session} 복원 — 붙이기: tmux switch-client -t ${session} (tmux 안) / tmux attach -t ${session}" >&2
            ;;
        session-restart)
            session=""
            [[ "${1:-}" == --* ]] || { session=${1:-}; shift || true; }
            session=$(resolveSession "${session}")
            parseRestoreFlags "$@"
            restartSession "${session}" "${force}" "${enter}"
            ;;
        *)
            sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
            exit 1
            ;;
    esac
}

main "$@"
