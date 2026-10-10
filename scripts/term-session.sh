#!/usr/bin/env bash
#
# 터미널 작업 환경 저장·복원 — 1단계: tmux pane 1개.
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
# 사용법:
#   term-session pane-save    [<pane>]                         # 레코드를 stdout 으로
#   term-session pane-restore <pane> <file|-> [--force] [--no-enter]
#   term-session pane-restart [<pane>] [--force] [--no-enter]  # 제자리 재시작 (save + restore)
#
# <pane> 은 tmux target (예: %3). 생략하면 현재 pane.
# TERM_SESSION_TMUX_SOCKET 를 주면 그 이름의 tmux 서버 (tmux -L) 를 쓴다 (시험용).

set -euo pipefail

readonly SESSIONS_DIR="${HOME}/.claude/sessions"
readonly PROJECTS_DIR="${HOME}/.claude/projects"

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

    jq -c --argjson args "${args}" --argjson env "${env}" --argjson transcript "${transcript}" \
        '{sessionId, name, status, args: $args, env: $env, transcript: $transcript}' "${sessionFile}"
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

    local line=""
    local pressEnter=0

    if jq -e '.claude' <<<"${record}" >/dev/null; then
        if jq -e '.claude.transcript' <<<"${record}" >/dev/null; then
            line=$(buildClaudeCommand "${record}" 1)
        else
            local name
            name=$(jq -r '.claude.name // empty' <<<"${record}")
            warn "대화 기록이 없어 새 세션으로 띄웁니다 — 들어가서 /catchup ${name} 를 실행하세요"
            line=$(buildClaudeCommand "${record}" 0)
        fi
        pressEnter=${enter}
    elif jq -e '.command' <<<"${record}" >/dev/null; then
        line=$(jq -r '.command' <<<"${record}")
    fi

    # 한 번의 tmux 호출로 묶는다 — 자기 pane 을 재시작하면 respawn 이 이 스크립트를 죽이지만
    # 명령은 이미 tmux 서버가 받았으므로 send-keys 까지 끝난다.
    local -a cmd=(respawn-pane -k -t "${pane}" -c "${cwd}")
    [[ -z "${line}" ]] || cmd+=(\; send-keys -t "${pane}" -l "${line}")
    (( ! pressEnter )) || cmd+=(\; send-keys -t "${pane}" Enter)

    echo "pane ${pane} ← ${line:-(빈 셸)}" >&2
    tm "${cmd[@]}"
}

parseRestoreFlags() {
    force=0
    enter=1

    local flag
    for flag in "$@"; do
        case "${flag}" in
            --force) force=1 ;;
            --no-enter) enter=0 ;;
            *) die "알 수 없는 옵션 — ${flag}" ;;
        esac
    done
}

main() {
    local subcommand=${1:-}
    shift || true

    local force enter pane record

    case "${subcommand}" in
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
        *)
            sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
            exit 1
            ;;
    esac
}

main "$@"
