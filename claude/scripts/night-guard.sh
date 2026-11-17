#!/usr/bin/env bash
# 야간 가드 — claude-loop 가 일을 맡긴 세션 (야간 모드) 에서 위험 동작에 확인창 (permissionDecision "ask") 을 띄운다.
# 확인창에서 멈추면 아침에 사람이 본다. 막히면 멈추는 쪽으로 안전하게 둔다 (2026-11-17 사용자 결정).
#
# 야간 모드 판정 (claude-loop.sh 와 맞춘다)
#   - 기존 세션: ~/.local/state/claude-loop/night/<session_id> 상태 파일이 있다 (러너가 메시지를 보내며 만든다)
#   - 러너가 새로 연 세션: 환경변수 CLAUDE_NIGHT=1 이고, 밤이 끝나지 않았고 (active 파일 — brief 가 지운다),
#     사람이 돌아와 풀지 않았다 (released/<session_id> 없음)
#
# 이벤트
#   - PreToolUse (Bash · Edit · Write · NotebookEdit · mcp__* · Agent · TeamCreate): 아래 위험 동작이면 ask.
#     팀메이트·새 세션·새 tmux window 도 막는다 — 세션 ID 가 달라 야간 모드 표시가 따라가지 않기 때문이다
#   - UserPromptSubmit: "[야간 루프" 로 시작하지 않는 입력 = 사람이 돌아옴 → 야간 모드를 푼다
#
# 서브에이전트 · 팀메이트 (agent_id 있음) 도 같은 세션으로 보고 막는다 — 다른 훅과 달리 agent_id 로 건너뛰지 않는다.
# 한계: 명령 문자열을 보는 목록 방식이라 목록 밖의 새 위험 동작은 막지 못한다. 브랜치 보호와 아침 요약의 사후 검토로 보완한다.
#
# set -e 를 쓰지 않는 이유: 모든 도구 호출에 도는 훅이라 예기치 못한 실패가 작업을 막으면 안 된다. 실패는 exit 0 으로 흡수한다.
set -uo pipefail

NIGHT_DIR="${HOME}/.local/state/claude-loop/night"

# push 를 보내면 배포·공용 이력에 닿는 브랜치
PROTECTED_BRANCH='(main|master|dev|develop|stag|staging|production|release[^[:space:]]*)'

input=$(cat)

IFS='|' read -r event tool_name session_id cwd < <(
  jq -r '[.hook_event_name // "", .tool_name // "", .session_id // "", .cwd // ""] | join("|")' <<<"${input}" 2>/dev/null
) || exit 0

[[ -n "${session_id}" ]] || exit 0

state_file="${NIGHT_DIR}/${session_id}"
released_file="${NIGHT_DIR}/released/${session_id}"

is_night_mode() {
  [[ -f "${state_file}" ]] || [[ "${CLAUDE_NIGHT:-}" == "1" && -f "${NIGHT_DIR}/active" && ! -f "${released_file}" ]]
}

emit_ask() {
  jq -n --arg reason "[야간 가드] $1 — 밤에는 하지 않는다. 아침에 사람이 판단" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# --- 사람이 돌아오면 야간 모드를 푼다 ---
if [[ "${event}" == "UserPromptSubmit" ]]; then
  is_night_mode || exit 0

  prompt=$(jq -r '.prompt // ""' <<<"${input}" 2>/dev/null)

  [[ "${prompt}" == "[야간 루프"* ]] && exit 0

  rm -f "${state_file}"
  mkdir -p "${NIGHT_DIR}/released" && touch "${released_file}"

  exit 0
fi

is_night_mode || exit 0

# --- Bash: 명령 전체 문자열에서 찾는다 (bash -c · timeout · env 같은 래퍼 안도 잡는다) ---
check_bash() {
  local command current_branch

  command=$(jq -r '.tool_input.command // ""' <<<"${input}")

  if grep -qE 'gh[[:space:]]+pr[[:space:]]+(merge|edit|comment|review|close|reopen|ready|lock)' <<<"${command}"; then
    emit_ask "PR 머지·수정·댓글·리뷰 (gh pr …)"
  fi

  if grep -qE 'gh[[:space:]]+(issue|release|label|secret|variable|repo)[[:space:]]' <<<"${command}" \
    && ! grep -qE 'gh[[:space:]]+(issue|release|label|secret|variable|repo)[[:space:]]+(view|list|status)' <<<"${command}"; then
    emit_ask "이슈·릴리스·라벨·시크릿·repo 변경 (gh …)"
  fi

  if grep -qE 'gh[[:space:]]+(run[[:space:]]+(rerun|cancel|delete)|workflow[[:space:]]+(run|enable|disable))' <<<"${command}"; then
    emit_ask "워크플로 실행·재실행 (gh run/workflow)"
  fi

  if grep -qE 'gh[[:space:]]+api' <<<"${command}" \
    && grep -qE '(-X|--method)[[:space:]=]*(PUT|POST|PATCH|DELETE)|graphql|[[:space:]](-f|-F|--field|--raw-field|--input)[[:space:]=]' <<<"${command}"; then
    emit_ask "GitHub API 쓰기 (gh api)"
  fi

  if grep -qE 'git[^;&|]*[[:space:]]push' <<<"${command}"; then
    if grep -qE "push[^;&|]*[[:space:]:+/]${PROTECTED_BRANCH}([[:space:]\"']|$)" <<<"${command}" \
      || grep -qE 'push[^;&|]*[[:space:]](--force|-f|--force-with-lease|--mirror|--all|--delete|-d|--tags)([[:space:]=]|$)|push[^;&|]*[[:space:]]:[^[:space:]]' <<<"${command}"; then
      emit_ask "보호 브랜치·강제·전체·삭제 push"
    fi

    current_branch=$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

    if grep -qxE "${PROTECTED_BRANCH}" <<<"${current_branch}"; then
      emit_ask "보호 브랜치 (${current_branch}) 에서 push"
    fi
  fi

  # 새 세션·window 는 세션 ID 가 달라 야간 모드 표시가 따라가지 않는다
  if grep -qE 'tmux[^;&|]*[[:space:]](new-window|neww|split-window|splitw|new-session|new|send-keys|send)([[:space:]]|$)' <<<"${command}" \
    || grep -qE '(^|[;&|(]|[[:space:]])claude[[:space:]]+(-n|--name|--bg|--background|-p|--print|-r|--resume|-c|--continue)([[:space:]=]|$)' <<<"${command}"; then
    emit_ask "새 Claude 세션·tmux window 열기 (야간 가드가 따라가지 않음)"
  fi

  if grep -qE 'gpgsign[[:space:]=]+false|--no-gpg-sign|insteadOf|credential\.helper|core\.sshCommand|GIT_SSH' <<<"${command}"; then
    emit_ask "커밋 서명·인증 방식 우회"
  fi

  if grep -qE '(^|[^[:alnum:]_./-])(aws|kubectl|terraform|atlantis|helm|argocd|mysql|psql)[[:space:]]' <<<"${command}"; then
    emit_ask "인프라·DB 명령 (aws·kubectl·terraform·mysql 등)"
  fi

  if grep -qE 'curl[^;&|]*([[:space:]](-X|--request)[[:space:]]*(POST|PUT|PATCH|DELETE)|[[:space:]](-d|--data[^[:space:]]*|-F|--form|-T|--upload-file)[[:space:]])' <<<"${command}"; then
    emit_ask "외부로 보내는 HTTP 요청 (curl 쓰기)"
  fi

  if grep -qE '\.github/|CLAUDE\.md|AGENTS\.(override\.)?md|\.dotfiles|/\.claude/|\.config/claude(/|[[:space:]]|$)|deploy-targets|claude-loop' <<<"${command}" \
    && grep -qE '>|tee[[:space:]]|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|(^|[[:space:];&|])(mv|cp|rm|ln)[[:space:]]' <<<"${command}"; then
    emit_ask "에이전트 지시·워크플로·hook 파일 수정 (셸)"
  fi
}

# --- Edit · Write: 다음 실행의 지시가 되거나 워크플로·hook 을 바꾸는 파일 ---
check_file() {
  local path

  path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"${input}")

  [[ -n "${path}" ]] || return 0

  case "${path}" in
    "${HOME}"/.claude/projects/*/memory/*) return 0 ;;
  esac

  case "${path}" in
    */.github/* | */CLAUDE.md | */AGENTS.md | */.claude/* | "${HOME}"/.dotfiles/* | "${HOME}"/.claude/* | "${HOME}"/.config/claude-loop/* | "${HOME}"/.config/claude/* | */AGENTS.override.md)
      emit_ask "에이전트 지시·워크플로·설정 파일 수정 (${path})"
      ;;
  esac
}

# --- MCP: 이름에 쓰기 동사가 있는 도구 · 쓰기 DB · 브라우저 ---
check_mcp() {
  local name

  name=$(tr '[:upper:]' '[:lower:]' <<<"${tool_name}")

  if grep -qE -- '-writer__|^mcp__aside__|execute-sql|(create|update|delete|merge|push|send|post|comment|transition|write|destructive|share|forward|reply|label|trash|edit|upload|move|restore|apply|draft|spam|respond|schedule|set_|add_)' <<<"${name}"; then
    emit_ask "쓰기 MCP 도구 (${tool_name})"
  fi
}

# --- 팀메이트: tmux 분할 창 팀메이트는 별도 프로세스라 세션 ID 가 달라 야간 가드 밖에서 돈다.
#     이름 없는 서브에이전트는 부모와 같은 session_id 로 들어와 가드가 걸린다 (2.1.326 실측) ---
check_agent() {
  local named

  named=$(jq -r '[.tool_input.name // "", .tool_input.team_name // ""] | join("")' <<<"${input}")

  if [[ "${tool_name}" == "TeamCreate" || -n "${named}" ]] \
    || [[ "$(jq -r '.tool_input.isolation // ""' <<<"${input}")" == "remote" ]]; then
    emit_ask "팀메이트·원격 에이전트 띄우기 (야간 가드가 따라가지 않음 — 밤에는 이름 없는 서브에이전트만)"
  fi
}

case "${tool_name}" in
  Bash) check_bash ;;
  Agent | Task | TeamCreate) check_agent ;;
  Edit | Write | NotebookEdit) check_file ;;
  mcp__*) check_mcp ;;
esac

exit 0
