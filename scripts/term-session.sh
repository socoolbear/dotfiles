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
#   term-session save    [-o <file>] [--handoff]     # 끄기 전에 (claude 가 살아 있을 때). --handoff: idle claude 마다 /handoff <이름>
#   term-session restore [<file>] [--mode resume|handoff] [--no-enter] [--dry-run]
#                                                    # 재부팅·Ghostty 재시작 뒤. resume (기본) = 같은 대화로,
#                                                    # handoff = 새 세션이 handoff 문서 (없으면 /catchup <ID>) 로 시작
#   term-session restart [--force] [--no-enter]      # Claude 버전업·zsh 설정 반영 (모든 세션 제자리 재시작)
#   term-session close   [-o <file>] [--yes]                   # handoff → 저장 → tmux·Ghostty 모두 닫기 (확인 창, --yes 면 생략)
#   term-session status                              # 마지막 저장 요약 한 줄
#   term-session run   <save|save-handoff|restore|restore-handoff|preview|restart>  # 창 없이 실행, 결과는 ~/.local/state/term-session/last.log (Alfred)
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
readonly HANDOFF_TIMEOUT=600
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

# /handoff 에 넘길 이름. 공백·경로 구분자·따옴표처럼 파일명이나 셸에서 곤란한 글자만 - 로 바꾼다 (한글은 그대로).
handoffSlug() {
    local name=$1

    tr " /:*?\"<>|\\\$\`'" '-' <<<"${name}"
}

# /handoff <이름> 이 쓰는 파일
handoffPath() {
    local cwd=$1
    local name=$2

    echo "${cwd}/.prompts/HANDOFF-$(handoffSlug "${name}").md"
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

    # handoff 문서가 있으면 경로와 작성 시각을 남긴다 (대화 기록이 정리돼도 이어갈 수 있게)
    local handoffFile handoff=null
    handoffFile=$(handoffPath "$(jq -r '.cwd' "${sessionFile}")" "$(jq -r '.name // .sessionId[0:8]' "${sessionFile}")")
    if [[ -f "${handoffFile}" ]]; then
        handoff=$(jq -cn --arg path "${handoffFile}" --argjson mtime "$(stat -f %m "${handoffFile}")" '{path: $path, mtime: $mtime}')
    fi

    jq -c --argjson args "${args}" --argjson env "${env}" --argjson transcript "${transcript}" --argjson lost "${lost}" \
        --argjson handoff "${handoff}" \
        '{sessionId, name, status, args: $args, env: $env, transcript: $transcript, lost: $lost, handoff: $handoff}' "${sessionFile}"
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

# 셸에 입력할 작은따옴표 문자열 (printf %q 는 한글을 $'\355…' 로 바꿔 history 가 읽기 어렵다)
quoteSingle() {
    local text=$1

    # shellcheck disable=SC2001 # bash 3.2 는 큰따옴표 안 치환에서 작은따옴표를 다르게 다뤄 sed 로 한다
    printf "'%s'\n" "$(sed "s/'/'\\\\''/g" <<<"${text}")"
}

# tail: 옵션 뒤에 붙일 것 (--resume <id> 또는 첫 메시지). 이미 셸 인용이 끝난 문자열.
buildClaudeCommand() {
    local record=$1
    local tail=$2

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

    [[ -z "${tail}" ]] || line+=" ${tail}"

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
        local sessionId handoffFile
        sessionId=$(jq -r '.claude.sessionId' <<<"${record}")
        handoffFile=$(jq -r '.claude.handoff.path // empty' <<<"${record}")

        if [[ "${restoreMode:-resume}" == resume ]] && jq -e '.claude.transcript' <<<"${record}" >/dev/null; then
            buildClaudeCommand "${record}" "--resume ${sessionId}"
            return
        fi
        [[ "${restoreMode:-resume}" == handoff ]] || warn "대화 기록이 없어 resume 대신 새 세션으로 띄웁니다"

        # 새 세션의 첫 메시지: handoff 문서 → 없으면 대화 기록으로 catchup (ID 로 지정해 고를 필요 없음).
        # 복원만으로 새 작업이 시작되지 않도록 요약까지만 시킨다.
        if [[ -n "${handoffFile}" && -f "${handoffFile}" ]]; then
            buildClaudeCommand "${record}" "$(quoteSingle "${handoffFile} 를 읽고 작업 상태를 짧게 요약해줘. 다음 작업은 내가 지시할 때까지 시작하지 마")"
        elif jq -e '.claude.transcript' <<<"${record}" >/dev/null; then
            buildClaudeCommand "${record}" "$(quoteSingle "/catchup ${sessionId:0:8}")"
        else
            warn "handoff 문서도 대화 기록도 없어 빈 새 세션으로 띄웁니다 — $(jq -r '.claude.name // empty' <<<"${record}")"
            buildClaudeCommand "${record}" ""
        fi
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
        set out to out & "W" & sep & (id of w) & linefeed
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

# claude 입력창이 비었는지 본다. 입력창 줄은 화면에서 ❯ 가 있는 마지막 줄이다.
# 빈 입력창은 ❯ 뒤가 비었거나 흐린 글씨 (ESC[2m) 의 안내 문구 ("Try …") 뿐이다.
# 쓰다 만 글이나 확인 창 선택지 (❯ 1. …) 가 있으면 비지 않은 것으로 본다 — 그 위에 입력하면 섞여 전송된다.
isClaudeInputEmpty() {
    local pane=$1

    local line
    line=$(tm capture-pane -e -p -t "${pane}" | grep '❯' | tail -1)
    line=${line#*❯}
    line=$(LC_ALL=C sed -e $'s/^\xc2\xa0//' -e 's/^ *//' <<<"${line}")

    [[ "${line}" != $'\e[2m'* ]] || return 0
    # shellcheck disable=SC2001 # 색상 코드를 바이트 단위로 지워야 해서 LC_ALL=C sed 를 쓴다
    [[ -z "$(LC_ALL=C sed $'s/\e\\[[0-9;]*m//g' <<<"${line}" | tr -d ' ')" ]]
}

# idle 인 claude 마다 /handoff <이름> 을 보내고, 일을 마치고 idle 로 돌아올 때까지 기다린다.
# 작업 중인 claude 는 하던 일을 방해하지 않도록 건너뛴다.
requestHandoffs() {
    local startEpoch failed=0
    startEpoch=$(date +%s)

    local -a pending=()
    local paneId shellPid claudePid sessionFile status name handoffFile
    while IFS= read -r paneId; do
        shellPid=$(tm display-message -p -t "${paneId}" '#{pane_pid}')
        claudePid=$(findClaudePid "${shellPid}")
        sessionFile="${SESSIONS_DIR}/${claudePid}.json"
        [[ -n "${claudePid}" && -f "${sessionFile}" ]] || continue

        status=$(jq -r '.status' "${sessionFile}")
        name=$(jq -r '.name // .sessionId[0:8]' "${sessionFile}")
        if [[ "${status}" != idle ]]; then
            warn "pane ${paneId} 의 claude (${name}) 는 ${status} 상태라 handoff 를 건너뜀 — 끝난 뒤 다시 저장하세요"
            failed=$((failed + 1))
            continue
        fi

        if ! isClaudeInputEmpty "${paneId}"; then
            warn "pane ${paneId} 의 claude (${name}) 입력창에 보내지 않은 글 (또는 확인 창) 이 있어 handoff 를 건너뜀 — 비운 뒤 다시 저장하세요"
            failed=$((failed + 1))
            continue
        fi

        handoffFile=$(handoffPath "$(jq -r '.cwd' "${sessionFile}")" "${name}")
        # vim 모드의 일반 모드면 입력 모드로 바꾼 뒤 입력한다 (Escape 는 보내지 않는다)
        if tm capture-pane -p -t "${paneId}" | grep -q -- '-- NORMAL --'; then
            tm send-keys -t "${paneId}" i
        fi
        tm send-keys -t "${paneId}" -l "/handoff $(handoffSlug "${name}")"
        tm send-keys -t "${paneId}" Enter

        echo "handoff 요청 — ${name} (pane ${paneId})" >&2
        pending+=("${sessionFile}${TAB}${handoffFile}${TAB}${name}${TAB}$(( $(date +%s) * 1000 ))")
    done < <(tm list-panes -a -F '#{pane_id}')

    local entry left sentAtMs
    while (( ${#pending[@]} > 0 && $(date +%s) - startEpoch < HANDOFF_TIMEOUT )); do
        sleep 5
        left=()
        for entry in "${pending[@]}"; do
            IFS=${TAB} read -r sessionFile handoffFile name sentAtMs <<<"${entry}"
            # 보낸 뒤에 일을 마치고 idle 로 돌아왔는지로 판단한다. 바뀐 게 없으면 claude 가 문서를 다시 쓰지 않으므로
            # 파일 시각은 기준이 될 수 없다 — 문서가 있기만 하면 된다.
            if [[ -f "${handoffFile}" ]] && jq -e --argjson sent "${sentAtMs}" \
                '.status == "idle" and .statusUpdatedAt >= $sent' "${sessionFile}" >/dev/null 2>&1; then
                echo "  ✓ ${name} → ${handoffFile}" >&2
                continue
            fi
            left+=("${entry}")
        done
        pending=(${left[@]+"${left[@]}"})
    done

    for entry in ${pending[@]+"${pending[@]}"}; do
        IFS=${TAB} read -r _ _ name _ <<<"${entry}"
        warn "${name} 의 handoff 가 ${HANDOFF_TIMEOUT}초 안에 끝나지 않음 — 그 claude 를 확인하세요"
        failed=$((failed + 1))
    done

    (( failed == 0 ))
}

# pane 하나에 빈 셸뿐인 세션 — Ghostty 를 열 때 zsh 가 자동으로 만든 세션이 대개 이렇다.
# 되살릴 내용이 없고, 저장·복원을 반복하면 이런 세션이 하나씩 쌓이므로 저장에서 빼고 복원 뒤 정리한다.
isEmptyShellSession() {
    local session=$1

    local panes
    panes=$(tm list-panes -s -t "=${session}" -F '#{pane_pid}')
    [[ $(wc -l <<<"${panes}") -eq 1 && -z "$(listDescendants "${panes}")" ]]
}

saveAll() {
    local outFile=$1

    local session sessions="" saved=""
    while IFS= read -r session; do
        if isEmptyShellSession "${session}"; then
            echo "세션 ${session} 은 빈 셸 하나뿐이라 저장하지 않음" >&2
            continue
        fi
        sessions+=$(snapshotSession "${session}")$'\n'
        saved+="${session}"$'\n'
    done < <(tm list-sessions -F '#{session_name}')

    # 저장하지 않은 세션의 Ghostty 탭도 뺀다 (복원할 때 열 수 없으므로)
    local ghostty
    ghostty=$(jq -c --argjson saved "$(jq -R . <<<"${saved%$'\n'}" | jq -s -c .)" \
        'map(.tabs |= map(select(.session as $s | $saved | index($s)))) | map(select(.tabs | length > 0))' \
        <<<"$(snapshotGhostty)")

    writeSnapshot "${outFile}" "$(jq -cn --argjson ghostty "${ghostty}" \
        --argjson sessions "$(jq -s . <<<"${sessions}")" '{ghostty: $ghostty, sessions: $sessions}')"
    reportSaved "${outFile}"
}

# 복원 뒤, 기록에 없는 빈 셸 세션 (Ghostty 를 열 때 생긴 것) 을 닫는다. zsh 가 tmux 와 함께 끝나 그 탭도 닫힌다.
# 이 명령을 그 세션 안에서 실행했을 수 있어 맨 마지막에 한다.
closeEmptySessions() {
    local nameMap=$1

    local session
    while IFS= read -r session; do
        awk -F '\t' -v s="${session}" '$2 == s { found = 1 } END { exit !found }' <<<"${nameMap}" && continue
        isEmptyShellSession "${session}" || continue

        if (( dryRun )); then
            echo "빈 세션 ${session} 을 닫음 (Ghostty 를 열 때 생긴 것)" >&2
            continue
        fi
        echo "빈 세션 ${session} 을 닫음 (Ghostty 를 열 때 생긴 것)" >&2
        tm kill-session -t "=${session}"
    done < <(tm list-sessions -F '#{session_name}')
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
    (( failedCount == 0 )) || warn "세션 ${failedCount} 개가 일부만 복원됨 (위 메시지 참고)"

    closeEmptySessions "${nameMap}"
    (( failedCount == 0 ))
}

# 정리할 것을 확인 창으로 보여 준다. "정리" 를 눌러야 0 을 돌려준다.
confirmClose() {
    local summary=$1

    osascript - "${summary}" <<'APPLESCRIPT' 2>/dev/null | grep -q '정리'
on run argv
    display dialog "아래를 handoff · 저장한 뒤 모두 닫습니다." & return & return & (item 1 of argv) ¬
        buttons {"취소", "정리"} default button "취소" cancel button "취소" with title "term-session 작업 정리"
end run
APPLESCRIPT
}

# 닫을 것 요약: 세션 수, claude 이름, 다른 프로그램 pane (닫으면 꺼짐)
describeClose() {
    local paneId shellPid claudePid child claudes="" programs="" sessionCount
    sessionCount=$(tm list-sessions | wc -l | tr -d ' ')

    while IFS= read -r paneId; do
        shellPid=$(tm display-message -p -t "${paneId}" '#{pane_pid}')
        claudePid=$(findClaudePid "${shellPid}")
        if [[ -n "${claudePid}" ]]; then
            claudes+="  · $(jq -r '.name // .sessionId[0:8]' "${SESSIONS_DIR}/${claudePid}.json" 2>/dev/null || echo "pid ${claudePid}")"$'\n'
            continue
        fi
        child=$(listDescendants "${shellPid}" | head -1)
        [[ -z "${child}" ]] || programs+="  · $(ps -o args= -p "${child}" | cut -c1-60)"$'\n'
    done < <(tm list-panes -a -F '#{pane_id}')

    printf 'tmux 세션 %s 개\n\nclaude (handoff 후 종료):\n%s' "${sessionCount}" "${claudes:-  · 없음}"
    [[ -z "${programs}" ]] || printf '\n다른 프로그램 (종료됨, 복원 때 명령만 입력):\n%s' "${programs}"
}

# Ghostty 창 가운데 tmux 세션 탭만 있는 창을 닫고, 남은 창이 없으면 Ghostty 를 끝낸다.
closeGhostty() {
    local sessions=$1

    local kind windowId title session closable windows=""
    while IFS=${TAB} read -r kind windowId _ title; do
        if [[ "${kind}" == "W" ]]; then
            [[ -z "${closable:-}" ]] || windows+="${closable}"$'\n'
            closable=${windowId}
            continue
        fi
        session=$(sessionFromTitle "${title}") && grep -qxF "${session}" <<<"${sessions}" || closable=""
    done < <(listGhosttyTabs)
    [[ -z "${closable:-}" ]] || windows+="${closable}"$'\n'

    while IFS= read -r windowId; do
        [[ -n "${windowId}" ]] || continue
        osascript -e "tell application \"Ghostty\" to close window (first window whose id is \"${windowId}\")" >/dev/null 2>&1 || true
    done <<<"${windows}"

    [[ -z "${TERM_SESSION_TMUX_SOCKET:-}" ]] || return 0
    if [[ "$(osascript -e 'tell application "Ghostty" to return (count of windows)' 2>/dev/null)" == "0" ]]; then
        echo "Ghostty 종료" >&2
        osascript -e 'tell application "Ghostty" to quit' >/dev/null 2>&1 || true
    fi
}

# handoff → 저장 → tmux 정리 → Ghostty 정리. handoff 를 하나라도 못 하면 아무것도 닫지 않는다.
closeAll() {
    local file=$1
    local assumeYes=$2

    tm has-session 2>/dev/null || die "닫을 tmux 세션이 없음"

    local summary
    summary=$(describeClose)
    echo "${summary}" >&2
    (( assumeYes )) || confirmClose "${summary}" || die "취소함"

    requestHandoffs || die "handoff 를 못 한 claude 가 있어 정리를 멈춤 (위 메시지 참고) — 아무것도 닫지 않았습니다"
    saveAll "${file}"

    local sessions
    sessions=$(tm list-sessions -F '#{session_name}')
    echo "tmux 정리 — 세션 $(wc -l <<<"${sessions}" | tr -d ' ') 개" >&2
    tm kill-server
    closeGhostty "${sessions}"
    echo "정리 끝 — 복원: Alfred ts → 복원 (resume) / 복원 (handoff 로 새 세션)" >&2
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

# 마지막 저장 요약 한 줄 (Alfred 표시용)
printStatus() {
    local file=$1

    if [[ ! -f "${file}" ]]; then
        echo "저장 기록 없음"
        return
    fi

    local ageMinutes
    ageMinutes=$(( ($(date +%s) - $(jq -r '.savedEpoch' "${file}")) / 60 ))

    local age="${ageMinutes}분 전"
    (( ageMinutes < 60 )) || age="$(( ageMinutes / 60 ))시간 전"
    (( ageMinutes < 1440 )) || age="$(( ageMinutes / 1440 ))일 전"

    jq -r --arg age "${age}" '
        "\(.savedAt[5:16] | sub("T"; " ")) 저장 (\($age)) · 세션 \(.sessions | length) · pane \([.. | objects | select(has("cwd"))] | length)"
        + " · claude \([.. | objects | select(has("claude"))] | length)"
        + ([.. | objects | select(.claude?) | .claude.lost // [] | .[]] | length | if . > 0 then " · 돌아오지 않을 작업 \(.)" else "" end)
    ' "${file}"
}

# 창 없이 실행하고 결과를 last.log 에 남긴다 (Alfred 용). TMUX_PANE 을 비워 모든 pane 이 대상이 되게 한다.
runLogged() {
    local action=$1

    local -a args
    case "${action}" in
        save) args=(save) ;;
        save-handoff) args=(save --handoff) ;;
        restore) args=(restore) ;;
        restore-handoff) args=(restore --mode handoff) ;;
        preview) args=(restore --dry-run) ;;
        restart) args=(restart) ;;
        close) args=(close) ;;
        *) die "알 수 없는 동작 — ${action}" ;;
    esac

    mkdir -p "${STATE_DIR}"
    local status=0
    {
        echo "[$(date '+%m-%d %H:%M:%S')] term-session ${args[*]}"
        TMUX_PANE="" "$0" "${args[@]}" 2>&1 || status=$?
        (( status == 0 )) || echo "→ 실패 (종료 코드 ${status})"
    } >"${STATE_DIR}/last.log"

    cat "${STATE_DIR}/last.log"
    return "${status}"
}

parseRestoreFlags() {
    force=0
    enter=1
    dryRun=0

    restoreMode=resume

    while (( $# > 0 )); do
        case "$1" in
            --force) force=1 ;;
            --no-enter) enter=0 ;;
            --dry-run) dryRun=1 ;;
            --mode) restoreMode=${2:-}; shift ;;
            *) die "알 수 없는 옵션 — $1" ;;
        esac
        shift
    done

    [[ "${restoreMode}" == resume || "${restoreMode}" == handoff ]] || die "--mode 는 resume 또는 handoff"

    (( ! dryRun )) || [[ "${subcommand}" == restore ]] || die "--dry-run 은 restore 에서만 쓸 수 있습니다"
}

main() {
    subcommand=${1:-}
    shift || true

    local force enter dryRun pane record session outFile withHandoff=0 assumeYes=0
    local snapshotFile="${STATE_DIR}/snapshot.json"

    case "${subcommand}" in
        save)
            while (( $# > 0 )); do
                case "$1" in
                    -o) snapshotFile=${2:?"-o 뒤에 파일 경로가 필요합니다"}; shift ;;
                    --handoff) withHandoff=1 ;;
                    *) die "알 수 없는 옵션 — $1" ;;
                esac
                shift
            done
            (( ! withHandoff )) || requestHandoffs
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
        close)
            while (( $# > 0 )); do
                case "$1" in
                    -o) snapshotFile=${2:?"-o 뒤에 파일 경로가 필요합니다"}; shift ;;
                    --yes) assumeYes=1 ;;
                    *) die "알 수 없는 옵션 — $1" ;;
                esac
                shift
            done
            closeAll "${snapshotFile}" "${assumeYes}"
            ;;
        status)
            printStatus "${snapshotFile}"
            ;;
        run)
            runLogged "${1:?"동작을 지정하세요 (save|restore|preview|restart)"}"
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
