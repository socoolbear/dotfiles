#!/usr/bin/env bash
# Bash · GitHub MCP 머지 PreToolUse 훅
# 배포를 일으키는 머지·push·workflow 실행 직전에 AGENTS.md "배포 확인 지점" 의 점검을 강제한다.
# repo 와 대상 브랜치로 dev 배포 / 운영 배포 / 미분류를 나눠 안내한다 (2026-11-17 사용자 결정).
#   - dev 배포: 사용자 확인 없이 진행하되, 실행 전 점검과 실행 후 dev 확인·QA 를 하게 한다
#   - 운영 배포: 점검 결과를 담아 사용자 확인을 받게 한다
#   - 미분류: repo 의 배포 workflow 트리거를 확인하게 한다 (조회 실패·cd 뒤 실행처럼 repo 를 확정 못 할 때 포함)
# 대상: gh pr merge, mcp__github__merge_pull_request, main/master/dev 로 가는 git push, gh workflow run, gh api …/dispatches
#
# 차단 방식 (2026-11-17 사용자 결정 — 운영 배포는 매번 확인):
#   - 대상마다 첫 실행은 exit 2 로 점검 목록을 준다 (증거를 모아 보고하게)
#   - 다시 실행하면 dev·미분류는 통과, 운영은 permissionDecision "ask" 로 확인창을 띄운다 (Yes = 사용자 확인).
#     -p 실행과 coolgom 세션은 답할 사람이 없어 자동 거부된다 (2.1.326 실측)
#   - AGENT_BOT=1 (coolgom 봇) 은 운영도 다시 실행하면 통과 — Slack 의 사용자 본인 승인을 확인으로 본다
#   - 야간 모드 (claude-loop 가 일을 맡긴 세션) 는 운영·dev·미분류 모두 처음부터 ask — 밤에는 dev 배포 점검을 할 수 없다
#
# 한계: 명령 문자열만 보므로 판단은 AGENTS.md 를 따른다.
# - push 는 git 이 명령 자리 (아래 COMMAND_START, VAR=값 접두 허용) 에 올 때만 잡는다.
#   브랜치가 명령에 없거나 HEAD 면 cwd 의 현재 브랜치로 정한다. --all · 셸 래퍼 (bash -c 등) 는 잡히지 않고,
#   커밋 메시지·heredoc 안의 같은 문자열은 잡힐 수 있다. 야간 모드의 래퍼·우회 경로는 night-guard.sh 가 막는다
# - workflow 실행은 development · stage · 브랜치 환경 workflow 가 명시되지 않으면 운영으로 본다
# - ArgoCD Sync 는 브라우저 (aside) 로 해서 잡히지 않는다
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/claude-deploy-check"
# 명령 자리 (줄 시작 또는 ; & | ( $( 뒤) 에 나온 경우만 잡는다 — 커밋 메시지·echo 안의 문자열을 빼려는 것 (완전하지 않다)
COMMAND_START='(^|[;&|(]|\$\()[[:space:]]*(command[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# 명령 안에서 작업 폴더를 옮기면 훅의 cwd 로 repo 를 정할 수 없다
CWD_MOVED='(^|[;&|(])[[:space:]]*(cd|pushd)[[:space:]]|git[[:space:]]+-C[[:space:]]'

# repo:브랜치 → 그 브랜치에 들어가면 일어나는 배포. 회사 repo 이름은 사내 보안 정책상 공개 저장소에 두지 않고
# 저장소 밖 비공개 파일에서 읽는다 (2026-11-17 사용자 결정 — 형식은 claude/deploy-targets.example, 표는 deploy-targets.md 와 맞춘다)
# 파일이 없으면 main·master·dev push 를 모두 운영으로 본다 — 모르면 운영 배포로 본다 (AGENTS.md)
TARGETS_FILE="${CLAUDE_DEPLOY_TARGETS:-${HOME}/.config/claude/deploy-targets}"
PROD_TARGETS=" "
DEV_TARGETS=" "
NODEPLOY_TARGETS=" "   # 서비스 배포가 없는 대상 (라이브러리 발행 등) — 묻지 않고 진행
DEV_WORKFLOW_PATTERN="development|stage"   # 이 단어가 든 workflow 실행만 dev — 사내 환경 이름은 비공개 파일의 dev-workflow 줄로 더한다
targets_missing=""

load_targets() {
  local kind target invalid_line=""

  if [[ -r "${TARGETS_FILE}" ]]; then
    while read -r kind target _; do
      # 형식이 어긋난 줄 (콜론 빠짐·대상 없음·모르는 종류) 이 하나라도 있으면 파일 전체를 믿지 않는다 — 모르면 운영
      if [[ "${kind}" == "dev-workflow" && "${target}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        DEV_WORKFLOW_PATTERN+="|${target}"
        continue
      fi

      if [[ ! "${kind}" =~ ^(prod|dev|none)$ || ! "${target}" =~ ^[^/[:space:]]+/[^:[:space:]]+:[^[:space:]]+$ ]]; then
        invalid_line=1
        continue
      fi

      case "${kind}" in
        prod) PROD_TARGETS+="${target} " ;;
        dev) DEV_TARGETS+="${target} " ;;
        none) NODEPLOY_TARGETS+="${target} " ;;
      esac
    done < <(tr -d '\r' <"${TARGETS_FILE}" | grep -vE '^[[:space:]]*(#|$)' || true)
  fi

  # 읽을 수 없거나, 형식이 어긋난 줄이 있거나, 운영 대상을 하나도 읽지 못했으면 파일이 없는 것과 같이 다룬다
  if [[ -n "${invalid_line}" || "${PROD_TARGETS}" == " " ]]; then
    targets_missing=1
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

# owner/repo 를 git 원격 URL 이나 PR URL 에서 뽑는다
extract_repo() {
  sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' <<<"$1" | cut -d/ -f1-2
}

is_cwd_moved() {
  grep -qE "${CWD_MOVED}" <<<"${command}"
}

# claude-loop 가 일을 맡긴 세션인가 — 판정은 night-guard.sh 와 같다
# (기존 세션은 상태 파일, 새로 연 세션은 CLAUDE_NIGHT=1 이고 사람이 돌아와 풀지 않았을 때)
is_night_mode() {
  local night_dir="${HOME}/.local/state/claude-loop/night"

  [[ -n "${session_id}" ]] || return 1
  [[ -f "${night_dir}/${session_id}" ]] \
    || [[ "${CLAUDE_NIGHT:-}" == "1" && -f "${night_dir}/active" && ! -f "${night_dir}/released/${session_id}" ]]
}

# push 대상 브랜치가 명령에 없거나 HEAD 뿐이면 cwd 의 현재 브랜치를 쓴다 (main·master·dev 일 때만 출력)
current_branch_if_implicit() {
  local segment="$1"
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

  git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null | grep -xE 'main|master|dev' || true
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

  pr_json=$(cd "${cwd:-.}" && gh pr view ${args[@]+"${args[@]}"} --json url,baseRefName 2>/dev/null || true)

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
  elif ! is_cwd_moved; then
    lookup_pr ${pr_ref:+"${pr_ref}"}
  fi
}

find_target() {
  local pr push_segments

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

    # dev 로 명시된 것만 dev, 나머지 (production·파일 입력·workflow ID 등) 는 운영으로 본다
    if grep -qiE "${DEV_WORKFLOW_PATTERN}" <<<"${command}"; then
      branch="dev"
    else
      branch="prod"
    fi

    return 0
  fi

  push_segments=$(grep -oE "${COMMAND_START}git[^;&|]*[[:space:]]push[^;&|]*" <<<"${command}" || true)
  branch=$(tr -d "\"'" <<<"${push_segments}" | grep -oE '[[:space:]:+](refs/heads/)?(main|master|dev)([[:space:]]|$)' | tail -1 | grep -oE 'main|master|dev' || true)

  if [[ -z "${branch}" && -n "${push_segments}" && "$(grep -c . <<<"${push_segments}")" == "1" ]] && ! is_cwd_moved; then
    branch=$(current_branch_if_implicit "$(tr -d "\"'" <<<"${push_segments}")")
  fi

  if [[ -z "${branch}" ]]; then
    return 0
  fi

  # 키에 refspec (해시) 까지 넣어 다른 커밋의 push 는 다시 점검하게 한다
  label="push ${cwd} ${push_segments//$'\n'/ | }"

  # push 가 여러 개거나 폴더를 옮겼으면 repo 를 하나로 정할 수 없어 미분류로 둔다
  if [[ "$(grep -c . <<<"${push_segments}")" == "1" ]] && ! is_cwd_moved; then
    repo=$(extract_repo "$(git -C "${cwd:-.}" remote get-url origin 2>/dev/null || true)")
  fi

  return 0
}

# dev / prod / unknown / none
classify() {
  if [[ -z "${label}" ]]; then
    echo none
  elif [[ "${repo}" == "workflow" ]]; then
    echo "${branch}"
  elif [[ "${NODEPLOY_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo none
  elif [[ "${PROD_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo prod
  elif [[ "${DEV_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo dev
  elif [[ -n "${targets_missing}" && "${branch}" =~ ^(main|master|dev)$ ]]; then
    echo prod
  elif [[ -z "${repo}" ]]; then
    echo unknown
  elif [[ -n "${branch}" && "${branch}" != "main" && "${branch}" != "master" ]]; then
    echo none
  else
    echo unknown
  fi
}

load_targets
find_target
kind=$(classify)
missing_note=""

if [[ -n "${targets_missing}" && "${repo}" != "workflow" ]]; then
  missing_note=$'\n'"(대상 파일 ${TARGETS_FILE} 을 읽지 못해 main·master·dev push 를 모두 운영으로 봅니다 — claude/deploy-targets.example 을 복사해 만드세요)"
fi

if [[ "${kind}" == "none" ]]; then
  exit 0
fi

if is_night_mode; then
  emit_ask "[야간 모드 배포 차단] ${label} → ${repo:-?}:${branch:-?} (${kind}). 밤에는 dev·운영 배포를 하지 않는다 — 아침에 사용자가 판단"
fi

# 대상마다 첫 실행만 점검 목록으로 차단한다. 다시 실행하면 운영은 확인창, 나머지는 통과
state_key=$(printf '%s %s' "${session_id}" "${label}" | md5 -q)
state_file="${STATE_DIR}/${state_key}"

if [[ -f "${state_file}" ]]; then
  if [[ "${kind}" == "prod" && "${AGENT_BOT:-}" != "1" ]]; then
    emit_ask "[운영 배포] ${repo:-?}:${branch} — ${label}. 점검 결과를 확인했으면 Yes"
  fi

  exit 0
fi

mkdir -p "${STATE_DIR}"
touch "${state_file}"

case "${kind}" in
  dev)
    cat >&2 <<EOF
[dev 배포 점검] ${label} → ${repo:-?}:${branch} 는 dev 배포입니다. 사용자 확인 없이 진행합니다.
기준: ~/.dotfiles/claude/AGENTS.md "배포 확인 지점" + 비공개 분류 표 ~/.config/claude/deploy-targets.md

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
기준: ~/.dotfiles/claude/AGENTS.md "배포 확인 지점" + 비공개 분류 표 ~/.config/claude/deploy-targets.md

점검 결과 (OK · 이슈 · 미확인) 를 담아 사용자 확인을 받는다:
- 범위 (함께 실리는 다른 커밋 목록) · CI·리뷰 · 선행 조건 · 호환성 · 검증 근거 · 독립 검증 · 되돌리기 (롤백 기준·관찰 시간)

- 결과를 응답에 적고 같은 명령을 다시 실행하면 확인창이 뜬다 (사용자가 Yes 를 눌러야 실행 — 봇 세션은 바로 통과)
- 사용자가 아직 이 대상을 요청·승인하지 않았으면: 다시 실행하기 전에 점검 결과와 함께 확인을 받는다
- 승인 뒤: 검토한 해시로 배포, 운영 QA, 롤백 기준에 걸리면 따로 묻지 않고 revert 하고 보고 (revert 도 이 확인창에서 Yes 가 필요하다)
EOF
    ;;
  unknown)
    cat >&2 <<EOF
[배포 점검] ${label} (${repo:-repo 미확인}:${branch:-?}) 은 배포 분류 표에 없는 대상입니다.
기준: ~/.dotfiles/claude/AGENTS.md "배포 확인 지점" + 비공개 분류 표 ~/.config/claude/deploy-targets.md

- repo 의 배포 workflow 트리거 (on:) 를 열어 이 동작이 운영 배포인지 확인한다. 모르면 운영 배포로 본다
- 운영 배포면: 점검 결과를 담아 사용자 확인 (요청·승인을 이미 받았으면 결과를 적고 다시 실행)
- 운영 배포가 아니면: 근거를 한 줄 적고 다시 실행. 자주 쓰는 repo 면 비공개 표 ~/.config/claude/deploy-targets.md 와 훅 대상 파일 ${TARGETS_FILE} 에 추가한다
EOF
    ;;
esac

exit 2
