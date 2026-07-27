#!/usr/bin/env bash
# ExitPlanMode PreToolUse 훅
# 계획서가 적대적 검증을 최소 1회 거치기 전에는 사용자에게 진행 여부를 묻지 못하게 차단한다.
# 통과 조건: 최신 계획서에 "## 적대적 검증" 섹션이 존재.
set -euo pipefail

MARKER="## 적대적 검증"
STATE_DIR="${TMPDIR:-/tmp}/claude-plan-review"

input=$(cat)

session_id=$(printf '%s' "${input}" | jq -r '.session_id // empty')
cwd=$(printf '%s' "${input}" | jq -r '.cwd // empty')

# plansDirectory 후보에서 가장 최근 수정된 계획서 경로를 반환 (없으면 빈 문자열)
find_latest_plan() {
  local base="${1}"
  local dir latest

  for dir in "${base}/.claude/plan" "${base}/.claude/plans"; do
    [[ -d "${dir}" ]] || continue

    latest=$(ls -t "${dir}"/*.md 2>/dev/null | head -1 || true)

    if [[ -n "${latest}" ]]; then
      printf '%s' "${latest}"
      return 0
    fi
  done

  return 0
}

plan_file=$(find_latest_plan "${cwd:-${PWD}}")

# 검증 섹션이 이미 있으면 통과
if [[ -n "${plan_file}" ]] && grep -qF "${MARKER}" "${plan_file}"; then
  exit 0
fi

# 무한 차단 방지: 계획서 (없으면 세션) 당 1회만 차단
state_key=$(printf '%s' "${plan_file:-${session_id}}" | md5 -q)
state_file="${STATE_DIR}/${state_key}"

if [[ -f "${state_file}" ]]; then
  exit 0
fi

mkdir -p "${STATE_DIR}"
touch "${state_file}"

cat >&2 <<EOF
[계획 검증 게이트] 이 계획서는 아직 적대적 검증을 거치지 않았습니다.
사용자에게 진행 여부를 묻기 전에 아래를 순서대로 수행한 뒤 ExitPlanMode 를 다시 호출하세요.

계획서: ${plan_file:-(자동 탐색 실패 — 계획 파일 경로를 직접 확인할 것)}

1. Agent 도구로 적대적 리뷰어 서브에이전트를 1개 이상 실행 (subagent_type: general-purpose).
   자기 계획을 스스로 검토하지 말 것 — 별도 에이전트에 "승인하지 말고 반박하라" 는 역할을 부여한다.
   전달할 것: 계획서 전문, 사용자의 원 요청, 변경 대상 파일 경로.
   반드시 답하게 할 것:
     a. 원 요청을 잘못 해석했거나 범위를 임의로 넓힌/좁힌 지점
     b. 빠진 케이스, 깨질 기존 동작 (회귀)
     c. 과설계 — 더 단순한 대안이 있는 부분
     d. 검증 절차의 허점 — 이 계획대로면 무엇이 증명되지 않는가
     e. 각 지적의 등급: BLOCKER (진행 불가) / MINOR (보완 권고)

2. BLOCKER 는 계획서를 고쳐 반드시 해소한다. MINOR 는 반영하거나 반영하지 않을 이유를 남긴다.

3. 계획서 맨 아래에 아래 섹션을 추가한다 (이 섹션이 있어야 게이트를 통과함).

   ## 적대적 검증
   - 리뷰어: <에이전트 수 / 라운드 수>
   - 지적 → 조치: <항목별로 반영 내용 또는 미반영 사유>
   - 남은 리스크: <있으면 명시, 없으면 "없음">

4. 그 다음 ExitPlanMode 를 호출한다.
EOF

exit 2
