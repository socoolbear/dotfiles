#!/usr/bin/env bash
# Bash · GitHub MCP 머지 PreToolUse 훅
# 배포를 일으키는 머지·push·workflow 실행 직전에 docs/deploy.md 의 점검을 강제한다.
# repo 와 대상 브랜치로 dev 배포 / 운영 배포 / 미분류를 나눠 안내한다 (2026-11-17 사용자 결정).
#   - dev 배포: 사용자 확인 없이 진행하되, 실행 전 점검과 실행 후 dev 확인·QA 를 하게 한다
#   - 운영 배포: 점검 결과를 담아 사용자 확인을 받게 한다
#   - 미분류: repo 의 배포 workflow 트리거를 확인하게 한다 (조회 실패·읽지 못한 폴더 이동처럼 repo 를 확정 못 할 때 포함)
# 대상: gh pr merge, mcp__github__merge_pull_request, main/master/dev 로 가는 git push, gh workflow run, gh api …/dispatches,
#       비공개 파일의 prod-command 줄에 걸린 명령 (git 을 거치지 않는 운영 배포 — FTP 업로드 스크립트 등)
#
# 차단 방식 (2026-11-17 사용자 결정 — 운영 배포는 매번 확인):
#   - 대상마다 첫 실행은 exit 2 로 점검 목록을 준다 (증거를 모아 보고하게)
#   - 다시 실행하면 dev·미분류는 통과, 운영과 repo 를 확정 못 한 미분류는 permissionDecision "ask" 로 확인창을 띄운다 (Yes = 사용자 확인).
#     repo 미확인을 통과시키면 폴더를 옮긴 뒤 실행한 운영 머지·push 가 확인창 없이 나간다 (2026-11-19 사용자 결정 — 모르면 운영)
#     확인은 이 확인창 한 번이다 — 에이전트는 점검 결과를 적고 대화로 따로 묻지 않는다 (2026-11-19 사용자 결정)
#     -p 실행과 coolgom 세션은 답할 사람이 없어 자동 거부된다 (2.1.326 실측)
#   - AGENT_BOT=1 (coolgom 봇) 은 운영도 다시 실행하면 통과 — Slack 의 사용자 본인 승인을 확인으로 본다
#   - coolgom 이 Slack 쓰레드에 연결해 띄운 태스크 세션 (COOLGOM_REPORT_DIR 있음) 도 운영을 다시 실행하면 통과한다
#     (2026-11-20 사용자 결정 — Slack 에서 대상을 짚어 요청한 뒤 터미널 확인창까지 눌러야 해 확인이 두 번이었다).
#     그 세션의 입력은 허용 사용자 본인의 Slack 답글과 터미널 입력뿐이다. repo 미확인과 prod-command 는 이 세션도 확인창을 띄운다
#   - 야간 모드 (claude-loop 가 일을 맡긴 세션) 는 운영·dev·미분류 모두 처음부터 ask — 밤에는 dev 배포 점검을 할 수 없다
#   - prod-command 에 걸린 명령은 점검 목록 없이 처음부터 ask (2026-11-18 사용자 결정) — 변경 내용 보고는 그 repo 의 배포 절차가 맡는다.
#     봇 세션도 예외 없이 ask 라 자동 거부된다 — 자리에 사람이 없을 때 git 밖 운영 배포가 나가지 않게
#
# 한계: 명령 문자열만 보므로 판단은 AGENTS.md 를 따른다.
# - push 는 git 이 명령 자리 (아래 COMMAND_START, VAR=값 접두 허용) 에 올 때만 잡는다.
#   브랜치가 명령에 없거나 HEAD 면 cwd 의 현재 브랜치로 정한다. --all · 셸 래퍼 (bash -c 등) 는 잡히지 않고,
#   커밋 메시지·heredoc 안의 같은 문자열은 잡힐 수 있다. 야간 모드의 래퍼·우회 경로는 night-guard.sh 가 막는다
# - workflow 실행은 입력값이 production·prod 면 운영, 아니면 development · stage · 비공개 dev-workflow 단어가 명시된 것만 dev, 나머지는 운영으로 본다
# - ArgoCD Sync 는 브라우저 (aside) 로 해서 잡히지 않는다
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/claude-deploy-check"
# 명령 자리 (줄 시작 또는 ; & | ( $( 뒤) 에 나온 경우만 잡는다 — 커밋 메시지·echo 안의 문자열을 빼려는 것 (완전하지 않다)
COMMAND_START='(^|[;&|(]|\$\()[[:space:]]*(command[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# 명령 안에서 작업 폴더를 옮기면 훅의 cwd 로 repo 를 정할 수 없다. 맨 앞의 `cd <경로> &&` 하나와 push 의 `git -C <경로>` 하나만 읽는다
# (태스크 루트에서 여는 세션이 쓰는 꼴). 그 밖의 이동 (cd 여러 번 · 서브셸 안 · pushd/popd · 변수·공백이 든 경로) 은 읽지 않고 repo 미확인으로 둔다
DIR_MOVE='(^|[;&|(])[[:space:]]*(cd|pushd|popd)([[:space:]]|$)'
LEADING_CD='^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*&&'

# repo:브랜치 → 그 브랜치에 들어가면 일어나는 배포. 회사 repo 이름은 사내 보안 정책상 공개 저장소에 두지 않고
# 저장소 밖 비공개 파일에서 읽는다 (2026-11-17 사용자 결정 — 형식은 claude/deploy-targets.example, 표는 deploy-targets.md 와 맞춘다)
# 파일이 없거나 깨졌으면 main·master·dev 는 운영, 표에 없는 다른 브랜치는 미분류로 본다 — 모르면 운영 배포로 본다 (AGENTS.md)
TARGETS_FILE="${CLAUDE_DEPLOY_TARGETS:-${HOME}/.config/claude/deploy-targets}"
PROD_TARGETS=" "
DEV_TARGETS=" "
NODEPLOY_TARGETS=" "   # 서비스 배포가 없는 대상 (라이브러리 발행 등) — 묻지 않고 진행
PROD_COMMANDS=()       # prod-command 줄의 정규식 — 명령 문자열에 맞으면 운영 배포
DEV_WORKFLOW_DEFAULT="development|stage"   # 이 문자열이 든 workflow 실행만 dev (부분 문자열)
# 사내 환경 이름은 비공개 파일의 dev-workflow 줄로 더한다 — 단어 단위로만 맞춘다 (예: pr 이 production 에 걸리지 않게)
DEV_WORKFLOW_PATTERN="${DEV_WORKFLOW_DEFAULT}"
targets_missing=""

# prod-command 정규식으로 쓸 수 있는가. 아래는 줄이 있어도 아무것도 못 잡거나 모든 명령을 잡으므로 형식 오류로 본다
# — 깨진 정규식 ([[ =~ ]] 가 2), 빈 문자열에 맞는 것 (모든 명령이 걸린다), \s·\d·\w·\b (bash ERE 에 없다), 따옴표로 시작하는 것 (따옴표째 맞춘다)
is_usable_command_regex() {
  local status=0

  [[ "$1" =~ \\[sdwbSDWB] || "$1" == [\"\']* ]] && return 1
  [[ "" =~ $1 ]] || status=$?

  [[ "${status}" == "1" ]]
}

load_targets() {
  local kind target extra invalid_line="" no_prod_declared="" has_prod=""

  if [[ -r "${TARGETS_FILE}" ]]; then
    while read -r kind target extra; do
      # 형식이 어긋난 줄 (콜론 빠짐·대상 없음·모르는 종류·칸이 더 있음) 은 invalid_line 으로 표시한다 — 아래에서 처리
      if [[ "${kind}" == "dev-workflow" && "${target}" =~ ^[A-Za-z0-9_-]+$ && -z "${extra}" ]]; then
        DEV_WORKFLOW_PATTERN+="|(^|[^[:alnum:]_])${target}([^[:alnum:]_]|$)"
        continue
      fi

      # prod-command <정규식> — 공백 없는 ERE 하나. 칸이 더 있으면 (줄 끝 주석 등) 파일은 깨진 것으로 보되 첫 칸 정규식은 쓴다
      if [[ "${kind}" == "prod-command" ]]; then
        if [[ -n "${target}" ]] && is_usable_command_regex "${target}"; then
          PROD_COMMANDS+=("${target}")
        else
          invalid_line=1
        fi

        [[ -z "${extra}" ]] || invalid_line=1
        continue
      fi

      # no-prod — 이 장비에는 운영 배포 대상이 없다고 밝히는 줄. 이 줄이 있어야 prod 줄 없는 파일을 정상으로 본다 (2026-11-18 사용자 결정)
      if [[ "${kind}" == "no-prod" && -z "${target}" ]]; then
        no_prod_declared=1
        continue
      fi

      if [[ ! "${kind}" =~ ^(prod|dev|none)$ || ! "${target}" =~ ^[^/[:space:]]+/[^:[:space:]]+:[^[:space:]]+$ ]]; then
        invalid_line=1
        continue
      fi

      # 칸이 더 있으면 (줄 끝 주석 등) 파일은 깨진 것으로 보되 첫 대상은 쓴다 — 운영 줄이 미분류로 빠지지 않게
      [[ -z "${extra}" ]] || invalid_line=1

      case "${kind}" in
        prod) PROD_TARGETS+="${target} " ;;
        dev) DEV_TARGETS+="${target} " ;;
        none) NODEPLOY_TARGETS+="${target} " ;;
      esac
    done < <(tr -d '\r' <"${TARGETS_FILE}" | grep -vE '^[[:space:]]*(#|$)' || true)
  fi

  [[ "${PROD_TARGETS}" != " " || ${#PROD_COMMANDS[@]} -gt 0 ]] && has_prod=1

  # 읽을 수 없거나, 형식이 어긋난 줄이 있거나, 운영 줄 (prod · prod-command) 이 하나도 없는데 no-prod 줄도 없으면 dev-workflow 단어를 버리고 main·master·dev 는 dev·none 줄보다 앞서 운영으로 본다 (classify)
  # — 오타 난 운영 줄과 같은 대상이 dev·none 으로 빠지지 않게. 다른 브랜치는 dev·none 줄대로, 표에 없으면 미분류로 본다. 모르면 운영
  # no-prod 줄과 운영 줄이 함께 있으면 서로 어긋나므로 깨진 파일로 본다
  if [[ -z "${has_prod}" && -z "${no_prod_declared}" ]] || [[ -n "${has_prod}" && -n "${no_prod_declared}" ]]; then
    invalid_line=1
  fi

  if [[ -n "${invalid_line}" ]]; then
    targets_missing=1
    DEV_WORKFLOW_PATTERN="${DEV_WORKFLOW_DEFAULT}"
  fi
}

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"${input}")
session_id=$(jq -r '.session_id // empty' <<<"${input}")
cwd=$(jq -r '.cwd // empty' <<<"${input}")
command=$(jq -r '.tool_input.command // empty' <<<"${input}")

repo=""
branch=""
label=""

# owner/repo 를 git 원격 URL 이나 PR URL 에서 뽑는다. SSH 는 github 로 시작하는 호스트 (계정 분리용 별칭 git@github-side:… 포함) 의
# owner/repo 두 단 경로만 받는다 — 다른 호스트나 하위 그룹 경로가 표의 대상과 같게 읽히면 안 된다 (그대로 두면 미분류)
extract_repo() {
  sed -E 's#\.git$##; s#^git@github[^:/]*:([^/]+/[^/]+)$#\1#; s#^https://github\.com/##' <<<"$1" | cut -d/ -f1-2
}

# 경로 (따옴표·~ 허용) 를 기준 폴더에서 풀어 실제 폴더면 절대 경로로 출력한다. 아니면 빈 값
resolve_dir() {
  local path="$1"
  local base="$2"

  path="${path%[\"\']}"
  path="${path#[\"\']}"
  path="${path/#\~/${HOME}}"
  (cd "${base}" 2>/dev/null && cd "${path}" 2>/dev/null && pwd) || true
}

# 명령이 실제로 도는 폴더. 읽지 못한 폴더 이동이 있으면 빈 값 (repo 미확인)
work_dir=""

resolve_work_dir() {
  local move_count

  work_dir="${cwd:-.}"
  move_count=$(grep -oE "${DIR_MOVE}" <<<"${command}" | grep -c . || true)

  if [[ "${move_count}" == "0" ]]; then
    return 0
  fi

  if [[ "${move_count}" == "1" && "${command}" =~ ${LEADING_CD} ]]; then
    work_dir=$(resolve_dir "${BASH_REMATCH[1]}" "${work_dir}")
    return 0
  fi

  work_dir=""
}

# push 한 줄이 도는 폴더 — `git -C <경로>` 가 하나 있으면 work_dir 에서 그 경로로, 여러 개면 빈 값
resolve_push_dir() {
  local segment="$1"
  local dir_args

  dir_args=$(grep -oE '[[:space:]]-C[[:space:]]+[^[:space:]]+' <<<"${segment}" | awk '{print $2}' || true)

  if [[ -z "${dir_args}" || -z "${work_dir}" ]]; then
    echo "${work_dir}"
  elif [[ "$(grep -c . <<<"${dir_args}")" == "1" ]]; then
    resolve_dir "${dir_args}" "${work_dir}"
  fi

  return 0
}

# claude-loop 가 일을 맡긴 세션인가 — 판정은 night-guard.sh 와 같다
# (기존 세션은 상태 파일, 새로 연 세션은 CLAUDE_NIGHT=1 이고 사람이 돌아와 풀지 않았을 때)
is_night_mode() {
  local night_dir="${HOME}/.local/state/claude-loop/night"

  [[ -n "${session_id}" ]] || return 1
  [[ -f "${night_dir}/${session_id}" ]] \
    || [[ "${CLAUDE_NIGHT:-}" == "1" && -f "${night_dir}/active" && ! -f "${night_dir}/released/${session_id}" ]]
}

# 사용자 본인의 Slack 요청을 운영 배포 확인으로 보는 세션인가 — coolgom 봇 세션, coolgom 이 Slack 쓰레드에 연결해 띄운 태스크 세션
is_slack_approved_session() {
  [[ "${AGENT_BOT:-}" == "1" || -n "${COOLGOM_REPORT_DIR:-}" ]]
}

# push 대상 브랜치가 명령에 없거나 HEAD 뿐이면 push 가 도는 폴더의 현재 브랜치를 쓴다 (main·master·dev 일 때만 출력)
current_branch_if_implicit() {
  local segment="$1"
  local push_dir="$2"
  local token
  local remote_seen=""
  local -a tokens
  local -a refspecs=()

  read -ra tokens <<<"${segment#*push}"

  for token in ${tokens[@]+"${tokens[@]}"}; do
    [[ "${token}" == -* ]] && continue

    if [[ -z "${remote_seen}" ]]; then
      remote_seen=1
      continue
    fi

    refspecs+=("${token}")
  done

  if (( ${#refspecs[@]} > 1 )) || [[ ${#refspecs[@]} == 1 && "${refspecs[0]}" != "HEAD" ]]; then
    return 0
  fi

  git -C "${push_dir}" rev-parse --abbrev-ref HEAD 2>/dev/null | grep -xE 'main|master|dev' || true
}

emit_ask() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# PR 의 repo·대상 브랜치를 조회한다 (실패하면 빈 값 — 미분류로 처리)
lookup_pr() {
  local -a args=("$@")
  local pr_json

  pr_json=$(cd "${work_dir:-${cwd:-.}}" && gh pr view ${args[@]+"${args[@]}"} --json url,baseRefName 2>/dev/null || true)

  if [[ -z "${pr_json}" ]]; then
    return 0
  fi

  repo=$(extract_repo "$(jq -r '.url' <<<"${pr_json}")")
  branch=$(jq -r '.baseRefName' <<<"${pr_json}")
}

# gh pr merge 의 PR 위치 인자와 -R 값을 뽑아 조회한다. 따옴표 문자열은 Q 로 바꿔 옵션 값으로만 소비한다
inspect_pr_merge() {
  local masked segment token
  local expect_value=""
  local pr_ref=""
  local repo_arg=""
  local -a tokens

  masked=$(sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g" <<<"${command}")
  segment=$(grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[^;&|]*' <<<"${masked}" | head -1 || true)
  read -ra tokens <<<"${segment#*merge}"

  for token in ${tokens[@]+"${tokens[@]}"}; do
    if [[ -n "${expect_value}" ]]; then
      if [[ "${expect_value}" == "repo" ]]; then
        repo_arg="${token}"
      fi

      expect_value=""
      continue
    fi

    case "${token}" in
      -R | --repo) expect_value="repo" ;;
      --repo=*) repo_arg="${token#--repo=}" ;;
      -t | --subject | -b | --body | -F | --body-file | -A | --author-email | --match-head-commit) expect_value="skip" ;;
      -*) ;;
      *)
        if [[ -z "${pr_ref}" ]]; then
          pr_ref="${token}"
        fi
        ;;
    esac
  done

  label="pr-merge ${cwd} ${repo_arg} ${pr_ref:-current-branch}"

  if [[ "${pr_ref}" == https://* ]]; then
    lookup_pr "${pr_ref}"
  elif [[ -n "${repo_arg}" ]]; then
    lookup_pr ${pr_ref:+"${pr_ref}"} -R "${repo_arg}"
  elif [[ -n "${work_dir}" ]]; then
    lookup_pr ${pr_ref:+"${pr_ref}"}
  fi
}

# Bash 명령이 비공개 파일의 prod-command 정규식에 맞는가
is_prod_command() {
  local prod_command

  [[ "${tool_name}" == "Bash" ]] || return 1

  for prod_command in ${PROD_COMMANDS[@]+"${PROD_COMMANDS[@]}"}; do
    [[ "${command}" =~ ${prod_command} ]] && return 0
  done

  return 1
}

find_target() {
  local pr push_segments
  local push_dir=""

  resolve_work_dir

  if [[ "${tool_name}" == "mcp__github__merge_pull_request" ]]; then
    pr=$(jq -r '.tool_input.pull_number // .tool_input.pullNumber' <<<"${input}")
    label=$(jq -r '"\(.tool_input.owner)/\(.tool_input.repo)#\(.tool_input.pull_number // .tool_input.pullNumber)"' <<<"${input}")
    lookup_pr "${pr}" -R "$(jq -r '"\(.tool_input.owner)/\(.tool_input.repo)"' <<<"${input}")"
    return 0
  fi

  [[ "${tool_name}" == "Bash" ]] || return 0

  if grep -qE "${COMMAND_START}gh[[:space:]]+pr[[:space:]]+merge" <<<"${command}"; then
    inspect_pr_merge
    return 0
  fi

  if grep -qE "${COMMAND_START}gh[[:space:]]+(workflow[[:space:]]+run|api[^;&|]*dispatches)" <<<"${command}"; then
    label="workflow-run ${cwd} ${command}"
    repo="workflow"

    # 입력값이 production·prod (environment=production 등) 면 dev 단어가 함께 있어도 운영. dev 로 명시된 것만 dev, 나머지 (파일 입력·workflow ID 등) 는 운영으로 본다
    if grep -qiE "[=:][[:space:]]*\\\\?[\"']?(production|prod)([^[:alnum:]_-]|\$)" <<<"${command}"; then
      branch="prod"
    elif grep -qiE "${DEV_WORKFLOW_PATTERN}" <<<"${command}"; then
      branch="dev"
    else
      branch="prod"
    fi

    return 0
  fi

  push_segments=$(grep -oE "${COMMAND_START}git[^;&|]*[[:space:]]push[^;&|]*" <<<"${command}" || true)
  branch=$(tr -d "\"'" <<<"${push_segments}" | grep -oE '[[:space:]:+](refs/heads/)?(main|master|dev)([[:space:]]|$)' | tail -1 | grep -oE 'main|master|dev' || true)

  if [[ -n "${push_segments}" && "$(grep -c . <<<"${push_segments}")" == "1" ]]; then
    push_dir=$(resolve_push_dir "$(tr -d "\"'" <<<"${push_segments}")")
  fi

  if [[ -z "${branch}" && -n "${push_dir}" ]]; then
    branch=$(current_branch_if_implicit "$(tr -d "\"'" <<<"${push_segments}")" "${push_dir}")
  fi

  if [[ -z "${branch}" ]]; then
    return 0
  fi

  # 키에 refspec (해시) 까지 넣어 다른 커밋의 push 는 다시 점검하게 한다
  label="push ${cwd} ${push_segments//$'\n'/ | }"

  # push 가 여러 개거나 도는 폴더를 읽지 못했으면 repo 를 하나로 정할 수 없어 미분류로 둔다
  if [[ -n "${push_dir}" ]]; then
    repo=$(extract_repo "$(git -C "${push_dir}" remote get-url origin 2>/dev/null || true)")
  fi

  return 0
}

# dev / prod / unknown / none
classify() {
  if [[ -z "${label}" ]]; then
    echo none
  elif [[ "${repo}" == "workflow" ]]; then
    echo "${branch}"
  elif [[ -n "${targets_missing}" && "${branch}" =~ ^(main|master|dev)$ ]]; then
    echo prod
  elif [[ "${PROD_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo prod   # 같은 대상이 prod·none 에 모두 있으면 운영 (모르면 운영)
  elif [[ "${NODEPLOY_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo none
  elif [[ "${DEV_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo dev
  elif [[ -z "${repo}" ]]; then
    echo unknown
  elif [[ -n "${branch}" && "${branch}" != "main" && "${branch}" != "master" && -z "${targets_missing}" ]]; then
    echo none
  else
    echo unknown
  fi
}

load_targets
find_target
kind=$(classify)
missing_note=""

if [[ -n "${targets_missing}" ]]; then
  missing_note=$'\n'"(대상 파일 ${TARGETS_FILE} 을 읽지 못했거나, 형식이 어긋난 줄이 있거나, 운영 (prod · prod-command) 줄도 no-prod 줄도 없어서 dev-workflow 단어를 쓰지 않고, main·master·dev 는 dev·배포 없음 줄과 상관없이 운영, 표에 없는 다른 브랜치는 미분류로 봅니다 — 고칠 곳은 표가 아니라 이 파일의 깨진 줄일 수 있습니다. 형식은 claude/deploy-targets.example)"
fi

prod_command_hit=""
is_prod_command && prod_command_hit=1

if [[ "${kind}" == "none" && -z "${prod_command_hit}" ]]; then
  exit 0
fi

if is_night_mode; then
  emit_ask "[야간 모드 배포 차단] ${label:-prod-command} → ${repo:-?}:${branch:-?} (${kind}). 밤에는 dev·운영 배포를 하지 않는다 — 아침에 사용자가 판단"
fi

# prod-command 만 걸렸으면 점검 목록 없이 바로 확인창. 같은 명령에 git 운영 배포도 있으면 아래 운영 흐름 (첫 실행 점검 목록) 을 탄다
if [[ -n "${prod_command_hit}" && "${kind}" != "prod" ]]; then
  emit_ask "[운영 배포] 비공개 표의 prod-command 에 걸린 명령입니다${label:+ (함께 실행: ${label})}. 변경 내용 (diff) 을 확인했으면 Yes"
fi

# 대상마다 첫 실행만 점검 목록으로 차단한다. 다시 실행하면 운영과 repo 미확인은 확인창, 나머지는 통과
state_key=$(printf '%s %s' "${session_id}" "${label}" | md5 -q)
state_file="${STATE_DIR}/${state_key}"

if [[ -f "${state_file}" ]]; then
  # 봇 세션 · Slack 연결 세션은 다시 실행하면 통과 — prod-command 가 함께 걸린 명령은 이 세션들도 확인창
  if [[ "${kind}" == "prod" ]] && { ! is_slack_approved_session || [[ -n "${prod_command_hit}" ]]; }; then
    emit_ask "[운영 배포] ${repo:-?}:${branch} — ${label}${prod_command_hit:+ + prod-command 에 걸린 명령}. 점검 결과를 확인했으면 Yes"
  fi

  # repo 를 확정 못 한 대상은 운영일 수 있다 — 모르면 운영. 봇 세션은 답할 사람이 없어 지금처럼 통과한다
  if [[ "${kind}" == "unknown" && -z "${repo}" && "${AGENT_BOT:-}" != "1" ]]; then
    emit_ask "[배포 대상 미확인] ${label} — 대상 repo 를 확정하지 못했습니다 (운영 배포일 수 있음). 운영이 아니거나 점검 결과를 확인했으면 Yes"
  fi

  exit 0
fi

mkdir -p "${STATE_DIR}"
touch "${state_file}"

case "${kind}" in
  dev)
    cat >&2 <<EOF
[dev 배포 점검] ${label} → ${repo:-?}:${branch} 는 dev 배포입니다. 사용자 확인 없이 진행합니다.${missing_note}
기준: ~/.dotfiles/claude/docs/deploy.md + 비공개 분류 표 ~/.config/claude/deploy-targets.md

실행 전 (결과를 응답에 적고 같은 명령을 다시 실행):
- 범위: diff 가 의도한 변경만 담는가
- repo 필수 체크·CI 통과, 봇 리뷰 지적 처리
- 독립 검증: 맥락을 물려받지 않은 에이전트가 diff 를 검토했는가
- dev 자동 배포되는 공용 main (비공개 표 참고): 운영 선행 조건이 준비됐거나 지금 운영에 나가도 문제없는 코드인가. 아니면 브랜치 환경으로

실행 후:
- dev 에 뜬 것이 이 커밋 빌드인지, 기동 로그로 외부 의존 연결 확인
- dev QA 후 결과 보고 (못 본 항목은 미확인). 실패하면 묻지 않고 revert 하거나 고친다
EOF
    ;;
  prod)
    cat >&2 <<EOF
[운영 배포 점검] ${label} → ${repo:-?}:${branch} 는 운영 배포입니다.${missing_note}
기준: ~/.dotfiles/claude/docs/deploy.md + 비공개 분류 표 ~/.config/claude/deploy-targets.md

아래를 점검해 내역은 태스크 notes.md (없으면 진행 문서) 에 쓰고, 응답에는 결론 한 줄과 결정을 바꿀 이슈·미확인만 적는다:
- 범위 (함께 실리는 다른 커밋 목록) · CI·리뷰 · 선행 조건 · 호환성 · 검증 근거 · 독립 검증 · 되돌리기 (롤백 기준·관찰 시간)

- 적은 뒤 대화로 따로 묻거나 턴을 끝내지 않고 같은 명령을 바로 다시 실행한다. 확인창이 뜨고, 사용자가 누르는 Yes 가 확인이다 (2026-11-19 사용자 결정 — 확인은 한 번)
- 봇 세션 (AGENT_BOT=1) 과 Slack 쓰레드에 연결된 태스크 세션은 확인창 없이 통과한다. 사용자 본인이 Slack 에서 이 대상을 짚어 요청했을 때만 다시 실행하고, 아니면 먼저 승인을 받는다
- 승인 뒤: 검토한 해시로 배포, 운영 QA, 롤백 기준에 걸리면 따로 묻지 않고 revert 하고 보고 (revert 도 이 확인창에서 Yes 가 필요하다)
EOF
    ;;
  unknown)
    cat >&2 <<EOF
[배포 점검] ${label} (${repo:-repo 미확인}:${branch:-?}) 은 배포 분류 표에 없는 대상입니다.${missing_note}
기준: ~/.dotfiles/claude/docs/deploy.md + 비공개 분류 표 ~/.config/claude/deploy-targets.md

- repo 의 배포 workflow 트리거 (on:) 를 열어 이 동작이 운영 배포인지 확인한다. 모르면 운영 배포로 본다
- 운영 배포면: 점검 결과를 담아 사용자 확인 (요청·승인을 이미 받았으면 결과를 적고 다시 실행)
- repo 미확인이면 다시 실행할 때 확인창이 뜬다. 폴더 이동을 명령 맨 앞의 cd 한 번으로 쓰거나 머지에 -R <owner/repo> 를 붙이면 repo 를 읽어 제대로 분류한다
- 운영 배포가 아니면: 근거를 한 줄 적고 다시 실행. 자주 쓰는 repo 면 비공개 표 ~/.config/claude/deploy-targets.md 와 훅 대상 파일 ${TARGETS_FILE} 에 추가한다
EOF
    ;;
esac

exit 2
