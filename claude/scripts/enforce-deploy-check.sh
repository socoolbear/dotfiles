#!/usr/bin/env bash
# Bash · GitHub MCP 머지 PreToolUse 훅
# 배포를 일으키는 머지·push·workflow 실행 직전에 AGENTS.md "배포 확인 지점" 의 점검을 강제한다.
# repo 와 대상 브랜치로 dev 배포 / 운영 배포 / 미분류를 나눠 안내한다 (2026-11-17 사용자 결정).
#   - dev 배포: 사용자 확인 없이 진행하되, 실행 전 점검과 실행 후 dev 확인·QA 를 하게 한다
#   - 운영 배포: 점검 결과를 담아 사용자 확인을 받게 한다
#   - 미분류: repo 의 배포 workflow 트리거를 확인하게 한다 (조회 실패·cd 뒤 실행처럼 repo 를 확정 못 할 때 포함)
# 대상: gh pr merge, mcp__github__merge_pull_request, main/master/dev 로 가는 git push, gh workflow run, gh api …/dispatches
#
# 한계: 명령 문자열만 보므로 판단은 AGENTS.md 를 따른다. 대상마다 1회만 차단하고, 같은 명령을 다시 실행하면 통과한다.
# - push 는 git 이 명령 자리 (아래 COMMAND_START, VAR=값 접두 허용) 에 오고 브랜치가 맨 이름으로 올 때만 잡는다.
#   git push · git push -u origin HEAD · --all 은 잡히지 않고, 커밋 메시지·heredoc 안의 같은 문자열은 잡힐 수 있다
# - workflow 실행은 development · stage · 브랜치 환경 workflow 가 명시되지 않으면 운영으로 본다
# - ArgoCD Sync 는 브라우저 (aside) 로 해서 잡히지 않는다
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/claude-deploy-check"
# 명령 자리 (줄 시작 또는 ; & | ( $( 뒤) 에 나온 경우만 잡는다 — 커밋 메시지·echo 안의 문자열을 빼려는 것 (완전하지 않다)
COMMAND_START='(^|[;&|(]|\$\()[[:space:]]*(command[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# 명령 안에서 작업 폴더를 옮기면 훅의 cwd 로 repo 를 정할 수 없다
CWD_MOVED='(^|[;&|(])[[:space:]]*(cd|pushd)[[:space:]]|git[[:space:]]+-C[[:space:]]'

# repo:브랜치 → 그 브랜치에 들어가면 일어나는 배포 (AGENTS.md "배포 확인 지점" 표와 맞춘다)
PROD_TARGETS=" imwebme/imweb:master imwebme/oms-api:main imwebme/billing-api:main "
DEV_TARGETS=" imwebme/msa:main imwebme/billing-api:dev imwebme/oms-api:dev "

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
  local pr push_segment

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
    if grep -qiE 'development|stage|branch-application' <<<"${command}"; then
      branch="dev"
    else
      branch="prod"
    fi

    return 0
  fi

  push_segment=$(grep -oE "${COMMAND_START}git[^;&|]*[[:space:]]push[^;&|]*" <<<"${command}" | head -1 || true)
  branch=$(tr -d "\"'" <<<"${push_segment}" | grep -oE '[[:space:]:+](refs/heads/)?(main|master|dev)([[:space:]]|$)' | tail -1 | grep -oE 'main|master|dev' || true)

  if [[ -z "${branch}" ]]; then
    return 0
  fi

  # 키에 refspec (해시) 까지 넣어 다른 커밋의 push 는 다시 점검하게 한다
  label="push ${cwd} ${push_segment}"

  if ! is_cwd_moved; then
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
  elif [[ "${PROD_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo prod
  elif [[ "${DEV_TARGETS}" == *" ${repo}:${branch} "* ]]; then
    echo dev
  elif [[ -z "${repo}" ]]; then
    echo unknown
  elif [[ -n "${branch}" && "${branch}" != "main" && "${branch}" != "master" ]]; then
    echo none
  else
    echo unknown
  fi
}

find_target
kind=$(classify)

if [[ "${kind}" == "none" ]]; then
  exit 0
fi

# 무한 차단 방지: 세션 · 대상당 1회만 차단
state_key=$(printf '%s %s' "${session_id}" "${label}" | md5 -q)
state_file="${STATE_DIR}/${state_key}"

if [[ -f "${state_file}" ]]; then
  exit 0
fi

mkdir -p "${STATE_DIR}"
touch "${state_file}"

case "${kind}" in
  dev)
    cat >&2 <<EOF
[dev 배포 점검] ${label} → ${repo:-?}:${branch} 는 dev 배포입니다. 사용자 확인 없이 진행합니다.
기준: ~/.dotfiles/claude/AGENTS.md "배포 확인 지점"

실행 전 (결과를 응답에 적고 같은 명령을 다시 실행):
- 범위: diff 가 의도한 변경만 담는가
- repo 필수 체크·CI 통과, 봇 리뷰 지적 처리
- 독립 검증: 맥락을 물려받지 않은 에이전트가 diff 를 검토했는가
- 공용 main (msa): 운영 선행 조건이 준비됐거나 지금 운영에 나가도 문제없는 코드인가. 아니면 브랜치 환경으로

실행 후:
- dev 에 뜬 것이 이 커밋 빌드인지, 기동 로그로 외부 의존 연결 확인
- dev QA 후 결과 보고 (못 본 항목은 미확인). 실패하면 묻지 않고 revert 하거나 고친다
EOF
    ;;
  prod)
    cat >&2 <<EOF
[운영 배포 점검] ${label} → ${repo:-?}:${branch} 는 운영 배포입니다.
기준: ~/.dotfiles/claude/AGENTS.md "배포 확인 지점"

점검 결과 (OK · 이슈 · 미확인) 를 담아 사용자 확인을 받는다:
- 범위 (함께 실리는 다른 커밋 목록) · CI·리뷰 · 선행 조건 · 호환성 · 검증 근거 · 독립 검증 · 되돌리기 (롤백 기준·관찰 시간)

- 이 세션에서 사용자가 이 대상을 지정해 요청·승인했으면: 결과를 적고 같은 명령을 다시 실행
- 아니면: 실행하지 말고 점검 결과와 함께 확인을 받는다
- 승인 뒤: 검토한 해시로 배포, 운영 QA, 롤백 기준에 걸리면 묻지 않고 revert 하고 보고
EOF
    ;;
  unknown)
    cat >&2 <<EOF
[배포 점검] ${label} (${repo:-repo 미확인}:${branch:-?}) 은 배포 분류 표에 없는 대상입니다.
기준: ~/.dotfiles/claude/AGENTS.md "배포 확인 지점"

- repo 의 배포 workflow 트리거 (on:) 를 열어 이 동작이 운영 배포인지 확인한다. 모르면 운영 배포로 본다
- 운영 배포면: 점검 결과를 담아 사용자 확인 (요청·승인을 이미 받았으면 결과를 적고 다시 실행)
- 운영 배포가 아니면: 근거를 한 줄 적고 다시 실행. 자주 쓰는 repo 면 AGENTS.md 표와 이 훅의 TARGETS 에 추가한다
EOF
    ;;
esac

exit 2
