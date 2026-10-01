#!/usr/bin/env bash
# PostToolUse 훅 — 컨텍스트 사용량이 자동 compact 기준의 50% / 80% 를 넘으면
# 진행 문서(.prompts/PROGRESS-<세션 앞 8자>.md)를 작성·갱신하라고 한 번씩 알린다.
#
# set -e 를 쓰지 않는 이유: 모든 도구 호출마다 도는 훅이라, 예기치 못한 실패가
# 종료 코드로 새어 나가면 작업 흐름이 깨진다. 실패는 전부 exit 0 으로 흡수한다.
#
# 한계: --autocompact CLI 플래그로 준 창 크기는 훅이 알 수 없다.
# (CLAUDE_CODE_AUTO_COMPACT_WINDOW 환경변수와 settings.json 의 autoCompactWindow 만 반영한다.)
set -uo pipefail

input=$(cat)

# --- 1. 구조적 가드 (transcript 를 읽기 전에 끝낸다) ---
# 구분자로 '|' 를 쓴다: IFS 가 공백문자면 빈 필드가 뭉개져 밀린다.
IFS='|' read -r agent_id perm_mode session_id transcript_path cwd < <(
  printf '%s' "${input}" | jq -r '
    [ .agent_id // "",
      .permission_mode // "",
      .session_id // "",
      .transcript_path // "",
      .cwd // ""
    ] | join("|")' 2>/dev/null
) || exit 0

[[ -n "${agent_id}" ]]         && exit 0   # 서브에이전트 컨텍스트
[[ "${perm_mode}" == "plan" ]] && exit 0   # 계획 모드에선 파일을 쓸 수 없다
[[ -n "${session_id}" ]]       || exit 0
[[ -f "${transcript_path}" ]]  || exit 0

# --- 2. 현재 사용 토큰 = 마지막 유효 assistant 라인의 usage 합계 ---
# <synthetic> 라인(usage 0) 은 건너뛴다. 모델명도 같은 라인에서 얻는다.
IFS='|' read -r used model < <(
  tail -n 200 "${transcript_path}" | jq -Rrs '
    split("\n")
    | map(fromjson? // empty)
    | map(select(.type == "assistant" and (.message.model // "") != "<synthetic>")
          | { model: (.message.model // ""),
              used: ((.message.usage.input_tokens // 0)
                   + (.message.usage.cache_creation_input_tokens // 0)
                   + (.message.usage.cache_read_input_tokens // 0)) }
          | select(.used > 0))
    | last // empty
    | "\(.used)|\(.model)"' 2>/dev/null
) || exit 0

[[ "${used}" =~ ^[0-9]+$ ]] || exit 0

# --- 3. 기준 토큰 (base) ---
# 창 우선순위: 환경변수 > settings.json autoCompactWindow > 모델 창. 최종값은 모델 창을 넘지 못한다.
model_window=1000000
[[ "${model}" == *haiku* ]] && model_window=200000

window="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"

if [[ ! "${window}" =~ ^[0-9]+$ ]]; then
  window=$(jq -r '.autoCompactWindow // empty' "${HOME}/.claude/settings.json" 2>/dev/null)
fi

[[ "${window}" =~ ^[0-9]+$ ]] || window="${model_window}"

base="${window}"
(( base > model_window )) && base="${model_window}"

pct_override="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}"

if [[ "${pct_override}" =~ ^[0-9]+$ ]] && (( pct_override >= 1 && pct_override <= 100 )); then
  base=$(( base * pct_override / 100 ))
fi

(( base > 0 )) || exit 0

# --- 4. 임계 단계 판정 ---
pct=$(( used * 100 / base ))
stage=0
(( pct >= 50 )) && stage=1
(( pct >= 80 )) && stage=2
(( stage > 0 )) || exit 0

# --- 5. 같은 단계는 한 번만 알린다 ---
state_dir="${TMPDIR:-/tmp}/claude-context-guard"
state_file="${state_dir}/${session_id}"
last_stage=0

[[ -f "${state_file}" ]] && last_stage=$(cat "${state_file}" 2>/dev/null)
[[ "${last_stage}" =~ ^[0-9]+$ ]] || last_stage=0

(( stage <= last_stage )) && exit 0

mkdir -p "${state_dir}" && printf '%s' "${stage}" > "${state_file}"

# --- 6. 진행 문서 작성 지시 주입 ---
project_dir="${CLAUDE_PROJECT_DIR:-${cwd}}"
progress_file="${project_dir}/.prompts/PROGRESS-${session_id:0:8}.md"

if (( stage == 2 )); then
  lead="컨텍스트 사용량이 ${pct}% (${used}/${base} 토큰) 입니다. 곧 자동 compact 됩니다. 진행 문서를 최신 상태로 갱신하세요."
else
  lead="컨텍스트 사용량이 ${pct}% (${used}/${base} 토큰) 입니다. 자동 compact 에 대비해 진행 문서를 지금 작성하세요."
fi

message="[컨텍스트 가드] ${lead}
경로: ${progress_file}
- 맨 위에 'session: ${session_id}' 와 실제 갱신 시각 (date 명령 결과) 을 적는다.
- 항목: 목표 / 완료 / 진행 중 (현재 단계·막힌 점) / 다음 단계 / 결정 사항과 이유 / 핵심 파일
- 짧게 쓰고, 기존 내용은 통째로 덮어쓴다.
- 하던 작업 흐름은 유지하되, 다음 도구 호출 전에 직접 처리한다. 서브에이전트에 위임하지 않는다."

jq -n --arg msg "${message}" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}' 2>/dev/null

exit 0
