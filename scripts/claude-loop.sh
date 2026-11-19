#!/usr/bin/env bash
#
# claude-loop — 사람이 없는 밤에 태스크 세션에 일을 맡기고 (night), 아침에 결과를 요약한다 (brief).
# launchd: com.socoolbear.claude-loop-night (매일 01:30) · com.socoolbear.claude-loop-brief (매일 08:30)
#
# 설계 (2026-11-17 사용자 결정): 새 헤드리스 쓰기 루프를 만들지 않는다. 같은 작업을 하는 세션이 열려 있으면
# 그 세션에 메시지를 보내고, 없으면 tmux 새 window 로 세션을 연다. 위험 동작은 야간 가드 hook 이 확인창 (ask) 으로 멈춘다.
#
# 대상 (opt-in): 태스크 notes.md 의 "## 루프" 절에 사용자가 적은 줄
#     - 세션: <세션 이름> | 검증: <검증 명령>
#   검증 명령은 사용자가 `claude-loop approve <세션>` 으로 승인한 값만 쓴다.
#   에이전트가 notes.md 를 고쳐 바뀐 명령은 승인될 때까지 그 세션을 건너뛴다 (밤에 임의 명령이 실행되는 경로 차단).
#
# 사용법
#   claude-loop night | brief | end | list | approve <세션> | board
#   board: 열려 있는 세션마다 상태와 상태 꼬리표 (지금 / 사용자 몫 / 다음) 를 한 화면에 보여준다 (상황판).
#          꼬리표는 Stop 훅 claude/scripts/stop-gate.sh 가 세션의 마지막 답변에서 복사해 둔 파일이다. 세션을 깨우지 않는다
#   CLAUDE_LOOP_DRY=1    판정만 출력 (상태 파일·메시지·새 세션 없음)
#   CLAUDE_LOOP_FORCE=1  실행 허용 구간 무시
#   끄기: touch ~/.local/state/claude-loop/disabled          (night · brief · 멈춤 점검 훅 전부)
#         touch ~/.local/state/claude-loop/night.disabled    (night 만 — 아침 요약과 멈춤 점검은 계속)
#
# 야간 모드 상태 (hook 4개 — night-guard · enforce-deploy-check · loop-verify-gate · ask-precheck — 가 같은 경로를 본다)
#   ~/.local/state/claude-loop/night/<session_id>  기존 세션에 보낸 기록 (JSON: name·verify·task_dir)
#   ~/.local/state/claude-loop/night/active        밤 진행 중 (새로 연 세션의 CLAUDE_NIGHT=1 이 유효한 조건)
#   brief 가 끝나면 end 로 모두 지운다. 사람이 세션에 입력하면 night-guard 가 그 세션만 먼저 푼다.

set -euo pipefail

export PATH="/opt/homebrew/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly DOTFILES="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
readonly WORKSPACE="${CLAUDE_LOOP_WORKSPACE:-${HOME}/code/workspace}"
readonly STATE_DIR="${HOME}/.local/state/claude-loop"
readonly NIGHT_DIR="${STATE_DIR}/night"
readonly APPROVED="${STATE_DIR}/approved.json"
readonly BOARD_DIR="${STATE_DIR}/board"
readonly LOG_DIR="${HOME}/Library/Logs/claude-loop"
readonly NIGHT_PROMPT="${DOTFILES}/claude/loop/night.md"
readonly BRIEF_PROMPT="${DOTFILES}/claude/loop/brief.md"
readonly METRICS="${DOTFILES}/claude/scripts/loop-metrics.sh"

# 실행 허용 구간 (시) — 잠든 맥이 깨어나 늦게 실행되면 건너뛴다
readonly NIGHT_WINDOW_START=0
readonly NIGHT_WINDOW_END=6
readonly BRIEF_WINDOW_START=7
readonly BRIEF_WINDOW_END=11

readonly DRY="${CLAUDE_LOOP_DRY:-}"
readonly MODE="${1:-}"
LOG=""

log() {
  printf '%s\n' "$1" | tee -a "${LOG:-/dev/null}"
}

notify() {
  [[ -n "${DRY}" ]] && return 0
  osascript -e "display notification \"$1\" with title \"claude-loop\"" >/dev/null 2>&1 || true
}

inWindow() {
  local hour

  [[ -n "${CLAUDE_LOOP_FORCE:-}" ]] && return 0

  hour=$((10#$(date +%H)))
  (( hour >= $1 && hour < $2 ))
}

acquireLock() {
  mkdir -p "${STATE_DIR}"

  if ! mkdir "${STATE_DIR}/lock" 2>/dev/null; then
    log "다른 claude-loop 가 실행 중 — 종료"
    exit 0
  fi

  trap 'rmdir "${STATE_DIR}/lock" 2>/dev/null || true' EXIT
}

loadSecrets() {
  # launchd 는 zshrc 를 읽지 않는다. gh 인증 토큰 (GITHUB_TOKEN) 을 직접 읽는다
  if [[ -f "${HOME}/.private-exports" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${HOME}/.private-exports"
    set -u
  fi
}

# notes.md 의 "## 루프" 절에서 "- 세션: 이름 | 검증: 명령" 을 뽑는다 → 태스크디렉토리<TAB>이름<TAB>검증
listEntries() {
  local notes

  for notes in "${WORKSPACE}"/*/tasks/*/notes.md; do
    [[ -f "${notes}" ]] || continue

    awk -v dir="$(dirname "${notes}")" '
      /^## / { inLoop = ($0 ~ /^## 루프[[:space:]]*$/); next }
      inLoop && /^- 세션:/ {
        line = $0
        sub(/^- 세션:[[:space:]]*/, "", line)
        verify = ""
        if (index(line, "| 검증:") > 0) {
          verify = substr(line, index(line, "| 검증:") + length("| 검증:"))
          line = substr(line, 1, index(line, "| 검증:") - 1)
        }
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", verify)
        gsub(/`/, "", verify)
        if (line != "") print dir "\t" line "\t" verify
      }
    ' "${notes}"
  done
}

approvedVerify() {
  [[ -f "${APPROVED}" ]] || { echo "__none__"; return 0; }
  jq -r --arg name "$1" 'if has($name) then .[$name] else "__none__" end' "${APPROVED}"
}

# claude agents --json 에서 이름이 같은 대화 세션 (가장 최근) 을 찾는다 → status<TAB>sessionId
findSession() {
  claude agents --json 2>/dev/null \
    | jq -r --arg name "$1" '[.[] | select(.name == $name and .kind == "interactive")] | sort_by(.startedAt) | last // empty | "\(.status)\t\(.sessionId)"'
}

# 이름이 같은 tmux window 의 첫 pane
findPane() {
  command tmux list-panes -a -F '#{window_name}	#{pane_index}	#{pane_id}' 2>/dev/null \
    | awk -F'\t' -v name="$1" '$1 == name { print $2 "\t" $3 }' | sort -n | head -1 | cut -f2
}

# 입력란에 사람이 쓰다 만 글이 있으면 보내지 않는다 (마지막 ❯ 줄 뒤가 비어 있어야 한다).
# 입력 제안 문구는 흐린 글씨 (ESC[2m … ESC[0m) 로 나오므로 그 구간을 빼고 본다 (2.1.326 실측)
isInputEmpty() {
  local rest

  rest=$(command tmux capture-pane -e -p -t "$1" 2>/dev/null \
    | LC_ALL=C grep -a $'\xe2\x9d\xaf' | tail -1 \
    | perl -pe 's/^.*?\xe2\x9d\xaf//; s/\e\[2m.*?(\e\[0m|\e\[22m|$)//g; s/\e\[[0-9;]*m//g; s/\xc2\xa0//g; s/\s+//g' || true)

  [[ -z "${rest}" ]]
}

nightMessage() {
  local verify="$1"
  local message="[야간 루프 자동 메시지 — 사용자 입력 아님] ${NIGHT_PROMPT} 를 읽고 그 지시대로 한 바퀴 진행하세요."

  if [[ -n "${verify}" ]]; then
    message+=" 검증 명령: ${verify}"
  fi

  printf '%s' "${message}"
}

deliverToSession() {
  local name="$1" verify="$2" taskDir="$3" sessionId="$4"
  local pane

  pane=$(findPane "${name}")

  if [[ -z "${pane}" ]]; then
    log "- ${name}: 건너뜀 (tmux window 를 찾지 못함 — tmux 밖에서 열린 세션)"
    return 0
  fi

  if ! isInputEmpty "${pane}"; then
    log "- ${name}: 건너뜀 (입력란에 쓰다 만 글이 있음)"
    return 0
  fi

  if [[ -n "${DRY}" ]]; then
    log "- ${name}: [dry] idle 세션 ${sessionId:0:8} 에 전달 예정 (pane ${pane})"
    return 0
  fi

  mkdir -p "${NIGHT_DIR}"
  jq -n --arg name "${name}" --arg verify "${verify}" --arg dir "${taskDir}" --arg at "$(date '+%F %T')" \
    '{name: $name, verify: $verify, task_dir: $dir, delivered_at: $at}' >"${NIGHT_DIR}/${sessionId}"

  command tmux send-keys -t "${pane}" -l "$(nightMessage "${verify}")"
  sleep 1
  command tmux send-keys -t "${pane}" Enter

  log "- ${name}: 전달 (세션 ${sessionId:0:8})"
}

openSession() {
  local name="$1" verify="$2" taskDir="$3"
  local target command inner

  target=$(command tmux list-sessions -F '#{session_last_attached} #{session_name}' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)

  if [[ -z "${target}" ]]; then
    log "- ${name}: 건너뜀 (tmux 서버 없음 — 새 세션을 열 곳이 없음)"
    return 0
  fi

  if [[ -n "${DRY}" ]]; then
    log "- ${name}: [dry] 세션 없음 → tmux '${target}' 에 새 window 로 열 예정 (${taskDir})"
    return 0
  fi

  # tmux 는 명령을 비대화형 셸로 돌려 zshrc (mise PATH 등) 가 빠진다 — 평소 window 와 같은 환경이 되게 대화형 로그인 zsh 로 감싼다
  inner="CLAUDE_NIGHT=1 CLAUDE_NIGHT_VERIFY=$(printf %q "${verify}") CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude -n $(printf %q "${name}") --permission-mode auto $(printf %q "$(nightMessage "${verify}")")"
  command="zsh -lic $(printf %q "${inner}"); exec zsh"
  command tmux new-window -d -t "${target}:" -n "${name}" -c "${taskDir}" "${command}"

  log "- ${name}: 새 세션 열고 전달 (tmux '${target}')"
}

runNight() {
  local taskDir name verify approved found status sessionId
  local entries

  inWindow "${NIGHT_WINDOW_START}" "${NIGHT_WINDOW_END}" || { log "실행 허용 구간 밖 — 건너뜀"; return 0; }

  entries=$(listEntries)

  if [[ -z "${entries}" ]]; then
    log "opt-in 된 세션 없음 (notes.md 의 '## 루프' 절)"
    return 0
  fi

  [[ -n "${DRY}" ]] || { mkdir -p "${NIGHT_DIR}" && touch "${NIGHT_DIR}/active"; }

  while IFS=$'\t' read -r taskDir name verify; do
    approved=$(approvedVerify "${name}")

    if [[ "${approved}" == "__none__" || "${approved}" != "${verify}" ]]; then
      log "- ${name}: 건너뜀 (검증 명령 미승인 — \`claude-loop approve ${name}\`)"
      continue
    fi

    found=$(findSession "${name}")

    if [[ -z "${found}" ]]; then
      openSession "${name}" "${verify}" "${taskDir}"
      continue
    fi

    IFS=$'\t' read -r status sessionId <<<"${found}"

    if [[ "${status}" != "idle" ]]; then
      log "- ${name}: 건너뜀 (세션 상태 ${status})"
      continue
    fi

    deliverToSession "${name}" "${verify}" "${taskDir}" "${sessionId}"
  done <<<"${entries}"
}

# brief 에 넘길 자료를 모은다 (도구 없이 요약만 하게)
collectBriefInput() {
  local taskDir name verify notes worktree since

  since="$(date -v-1d '+%Y-%m-%d') 20:00"

  echo "# 야간 로그"
  cat "${LOG_DIR}/$(date '+%F')-night.md" 2>/dev/null || echo "(오늘 야간 로그 없음)"

  echo
  echo "# 세션별 자료"

  while IFS=$'\t' read -r taskDir name verify; do
    [[ -n "${taskDir}" ]] || continue

    echo
    echo "## ${name} (${taskDir})"
    echo "### 진행 문서의 「야간 결과」 (최근 수정 진행 문서 기준)"
    notes=$(ls -t "${taskDir}"/.prompts/PROGRESS-*.md 2>/dev/null | head -1 || true)

    if [[ -n "${notes}" ]]; then
      awk '/^#+ .*야간 결과/ { show = 1; print; next } show && /^#+ / { show = 0 } show' "${notes}" | head -60
    fi

    echo "### [loop] 커밋 (어제 20시 이후)"

    for worktree in "${taskDir}"/*/; do
      git -C "${worktree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
      git -C "${worktree}" log --all --since="${since}" --grep='^\[loop\]' --format="${worktree##*/tasks/} %h %s (%ar)" --shortstat 2>/dev/null | grep . || true
    done
  done <<<"$(listEntries)"

  echo
  echo "# 질문 대기열 (태스크 notes.md)"

  for notes in "${WORKSPACE}"/*/tasks/*/notes.md; do
    [[ -f "${notes}" ]] || continue
    awk -v file="${notes#"${WORKSPACE}"/}" '/^## 질문 대기열/ { show = 1; print "## " file; next } show && /^## / { show = 0 } show' "${notes}"
  done

  echo
  echo "# 내 열린 PR"
  gh search prs --author @me --state open --json repository,number,title,url,isDraft --limit 50 2>/dev/null \
    | jq -r '.[] | "\(.repository.nameWithOwner)\t\(.number)\t\(.isDraft)\t\(.title)\t\(.url)"' \
    | while IFS=$'\t' read -r repo number draft title url; do
        gh pr view "${number}" -R "${repo}" --json reviewDecision,statusCheckRollup,headRefName 2>/dev/null \
          | jq -r --arg head "${repo}#${number} draft=${draft} ${title} ${url}" \
            '"- \($head) | 브랜치 \(.headRefName) | 리뷰 \(.reviewDecision // "없음") | CI 실패 \([.statusCheckRollup[]? | select((.conclusion // .state) as $s | ["FAILURE","ERROR","TIMED_OUT","CANCELLED"] | index($s))] | length)건 · 진행 \([.statusCheckRollup[]? | select((.status // "") == "IN_PROGRESS" or (.state // "") == "PENDING")] | length)건"' \
          || echo "- ${repo}#${number} ${title} (조회 실패)"
      done || echo "(PR 조회 실패 — gh 인증 확인)"

  echo
  echo "# 상황판 (열린 세션의 상태 꼬리표)"
  runBoard 2>/dev/null || echo "(상황판 조회 실패)"

  echo
  echo "# 질문 지표"
  bash "${METRICS}" 1 2>/dev/null || echo "(지표 계산 실패)"

  echo
  echo "# 멈춤 점검 기록 (최근 24시간, 모드: $(cat "${STATE_DIR}/stop-gate/mode" 2>/dev/null || echo record))"
  jq -rs --arg since "$(date -v-1d '+%FT%T')" '
    map(select(.at >= $since and (.reentry | not)))
    | "끝난 턴 \(length)건 · 글 질문 \(map(select(.asks)) | length)건 · 꼬리표 있음 \(map(select(.footer)) | length)건 · 사용자 몫 있음 \(map(select(.owes)) | length)건 (분류 없어 막힘 \(map(select(.owes and (.tagged | not))) | length)건) · 다음 일을 남기고 멈춤 \(map(select(.next == "todo")) | length)건",
      "글 질문 표본 (끝 80자):",
      (map(select(.asks)) | .[-8:][] | "- \(.tail[-80:])")' "${STATE_DIR}/stop-gate/log.jsonl" 2>/dev/null || echo "(기록 없음)"
}

runBrief() {
  local input report

  inWindow "${BRIEF_WINDOW_START}" "${BRIEF_WINDOW_END}" || { log "실행 허용 구간 밖 — 건너뜀"; return 0; }

  input=$(collectBriefInput)
  report="${LOG_DIR}/$(date '+%F')-brief.md"

  if [[ -n "${DRY}" ]]; then
    printf '%s\n' "${input}"
    return 0
  fi

  # 도구 없이 요약만 한다 (내장 도구 없음 + MCP 설정 없음 + dontAsk → 남은 도구 호출도 모두 거부)
  printf '%s\n' "${input}" \
    | (cd "${STATE_DIR}" && timeout 600 claude -p --permission-mode dontAsk --tools "" \
      --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
      --append-system-prompt "$(cat "${BRIEF_PROMPT}")" "표준 입력의 자료로 아침 보고를 써 주세요.") >"${report}" 2>>"${LOG}" \
    || log "요약 생성 실패 — 자료만 저장"

  if [[ ! -s "${report}" ]]; then
    printf '%s\n' "${input}" >"${report}"
  fi

  log "보고서: ${report}"
  notify "아침 보고가 준비됐어요 — $(head -c 120 "${report}" | tr '\n' ' ' | tr -d '"')"
  runEnd
}

runEnd() {
  [[ -n "${DRY}" ]] && return 0
  rm -f "${NIGHT_DIR}"/* "${NIGHT_DIR}"/released/* "${NIGHT_DIR}"/blocks/* 2>/dev/null || true
  log "야간 모드 종료 (상태 파일 정리)"
}

runList() {
  local taskDir name verify approved state

  while IFS=$'\t' read -r taskDir name verify; do
    [[ -n "${name}" ]] || continue
    approved=$(approvedVerify "${name}")

    if [[ "${approved}" == "${verify}" ]]; then state="승인됨"; else state="미승인"; fi

    printf '%s\t%s\t검증: %s\t%s\n' "${state}" "${name}" "${verify:-(없음)}" "${taskDir#"${WORKSPACE}"/}"
  done <<<"$(listEntries)"
}

runApprove() {
  local target="$1"
  local verify

  verify=$(listEntries | awk -F'\t' -v name="${target}" '$2 == name { print $3; exit }')

  if ! listEntries | awk -F'\t' -v name="${target}" '$2 == name { found = 1 } END { exit !found }'; then
    echo "notes.md '## 루프' 절에 '- 세션: ${target}' 줄이 없습니다" >&2
    exit 1
  fi

  mkdir -p "${STATE_DIR}"
  [[ -f "${APPROVED}" ]] || echo '{}' >"${APPROVED}"
  jq --arg name "${target}" --arg verify "${verify}" '.[$name] = $verify' "${APPROVED}" >"${APPROVED}.tmp"
  mv "${APPROVED}.tmp" "${APPROVED}"

  echo "승인: ${target} — 검증: ${verify:-(없음)}"
}

# 상황판 — 열려 있는 대화 세션을 사용자 몫이 있는 것부터 보여준다
runBoard() {
  local name status sessionId cwd file age waiting
  local separator=$'\x1f'
  local now

  now=$(date +%s)

  claude agents --json 2>/dev/null \
    | jq -r '.[] | select(.kind == "interactive") | [(.name // ""), .status, .sessionId, .cwd] | join("\u001f")' \
    | while IFS="${separator}" read -r name status sessionId cwd; do
        file="${BOARD_DIR}/${sessionId}.md"
        waiting=1

        # 사용자 몫이 "없음" 이 아닌 세션을 위로 올린다 (정렬 키 0)
        if [[ -f "${file}" ]] && grep -qE '^\*\*사용자 몫:?\*\*' "${file}" && ! grep -qE '^\*\*사용자 몫:?\*\*[^가-힣A-Za-z0-9]*없음' "${file}"; then
          waiting=0
        fi

        printf '%s%s%s%s%s%s%s%s%s\n' "${waiting}" "${separator}" "${name:-${cwd##*/}}" "${separator}" "${status}" "${separator}" "${sessionId}" "${separator}" "${cwd}"
      done \
    | sort -t "${separator}" -k1,1 -k2,2 \
    | while IFS="${separator}" read -r waiting name status sessionId cwd; do
        file="${BOARD_DIR}/${sessionId}.md"

        if [[ ! -f "${file}" ]]; then
          printf '\n■ %s [%s] — 꼬리표 없음 (%s)\n' "${name}" "${status}" "${cwd/#${HOME}/~}"
          continue
        fi

        age=$(( (now - $(stat -f %m "${file}")) / 60 ))
        printf '\n■ %s [%s] — %s분 전%s\n' "${name}" "${status}" "${age}" "$([[ "${waiting}" == "0" ]] && echo ' 🔔 사용자 몫')"
        sed 's/^/  /' "${file}"
      done
}

main() {
  case "${MODE}" in
    night | brief)
      [[ -f "${STATE_DIR}/disabled" ]] && { echo "claude-loop 꺼짐 (${STATE_DIR}/disabled)"; exit 0; }
      [[ "${MODE}" == "night" && -f "${STATE_DIR}/night.disabled" ]] && { echo "야간 루프 꺼짐 (${STATE_DIR}/night.disabled)"; exit 0; }
      mkdir -p "${LOG_DIR}"
      LOG="${LOG_DIR}/$(date '+%F')-${MODE}.md"
      acquireLock
      loadSecrets
      log "## $(date '+%F %T') ${MODE}${DRY:+ (dry)}"

      if [[ "${MODE}" == "night" ]]; then
        runNight
        notify "야간 루프: $(grep -c '^- ' "${LOG}" 2>/dev/null || echo 0)건 처리 — 로그 ${LOG}"
      else
        runBrief
      fi
      ;;
    end) runEnd ;;
    list) runList ;;
    approve) runApprove "${2:?세션 이름}" ;;
    board) runBoard ;;
    *)
      echo "사용법: claude-loop night | brief | end | list | approve <세션> | board" >&2
      exit 1
      ;;
  esac
}

main "$@"
