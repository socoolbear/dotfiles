#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

# 변수 초기화 (set -u 대응)
model="" used_pct="" vim_mode="" cost_usd="" duration_ms=""
lines_added="" lines_removed="" total_in="" total_out=""
cache_read="" input_tokens="" exceeds_200k="" agent_name=""

# 단일 jq 호출로 모든 필드 추출
eval "$(echo "${input}" | jq -r '
  @sh "model=\(.model.display_name // empty)",
  @sh "used_pct=\(.context_window.used_percentage // empty)",
  @sh "vim_mode=\(.vim.mode // empty)",
  @sh "cost_usd=\(.cost.total_cost_usd // empty)",
  @sh "duration_ms=\(.cost.total_duration_ms // empty)",
  @sh "lines_added=\(.cost.total_lines_added // empty)",
  @sh "lines_removed=\(.cost.total_lines_removed // empty)",
  @sh "total_in=\(.context_window.total_input_tokens // empty)",
  @sh "total_out=\(.context_window.total_output_tokens // empty)",
  @sh "cache_read=\(.context_window.current_usage.cache_read_input_tokens // empty)",
  @sh "input_tokens=\(.context_window.current_usage.input_tokens // empty)",
  @sh "exceeds_200k=\(.exceeds_200k_tokens // empty)",
  @sh "agent_name=\(.agent.name // empty)"
')"

# --- ANSI 색상 ---
RESET=$'\033[0m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'

# --- 헬퍼 함수 ---

# 토큰 K/M 축약: 1500 → 1.5k, 1500000 → 1.5M
format_tokens() {
  local n="${1:-0}"

  if [[ "${n}" -ge 1000000 ]]; then
    awk "BEGIN { printf \"%.1fM\", ${n} / 1000000 }"
  elif [[ "${n}" -ge 1000 ]]; then
    awk "BEGIN { printf \"%.1fk\", ${n} / 1000 }"
  else
    echo "${n}"
  fi
}

# ms → 시간 표시: 60000 → 1m, 3600000 → 1h0m
format_duration() {
  local ms="${1:-0}"
  local total_sec=$(( ms / 1000 ))
  local hours=$(( total_sec / 3600 ))
  local mins=$(( (total_sec % 3600) / 60 ))

  if [[ "${hours}" -gt 0 ]]; then
    echo "${hours}h${mins}m"
  else
    echo "${mins}m"
  fi
}

# 프로그레스 바: 45 → [████░░░░░░] (10칸)
progress_bar() {
  local pct="${1:-0}"
  local pct_int=${pct%.*}
  local filled=$(( pct_int / 10 ))
  local empty=$(( 10 - filled ))
  local bar=""

  for (( i = 0; i < filled; i++ )); do
    bar+="█"
  done

  for (( i = 0; i < empty; i++ )); do
    bar+="░"
  done

  echo "[${bar}]"
}

# --- 각 요소 렌더링 ---
parts=()

# 1. 세션 건강 인디케이터
health="🟢"
if [[ -n "${cost_usd}" ]]; then
  cost_int=$(awk "BEGIN { printf \"%d\", ${cost_usd} }")

  if [[ "${cost_int}" -ge 5 ]]; then
    health="🔴"
  elif [[ "${cost_int}" -ge 2 ]]; then
    health="🟡"
  fi
fi

if [[ -n "${duration_ms}" ]]; then
  dur_min=$(( duration_ms / 60000 ))

  if [[ "${dur_min}" -ge 120 ]]; then
    health="🔴"
  elif [[ "${dur_min}" -ge 60 && "${health}" != "🔴" ]]; then
    health="🟡"
  fi
fi

if [[ -n "${used_pct}" ]]; then
  ctx_int=${used_pct%.*}

  if [[ "${ctx_int}" -ge 85 ]]; then
    health="🔴"
  elif [[ "${ctx_int}" -ge 70 && "${health}" != "🔴" ]]; then
    health="🟡"
  fi
fi

parts+=("${health}")

# 2. 200k 초과 경고
if [[ "${exceeds_200k}" == "true" ]]; then
  parts+=("${RED}[!200k]${RESET}")
fi

# 3. 컨텍스트 프로그레스 바
if [[ -n "${used_pct}" ]]; then
  ctx_int=${used_pct%.*}
  bar=$(progress_bar "${ctx_int}")

  if [[ "${ctx_int}" -ge 80 ]]; then
    ctx_color="${RED}"
  elif [[ "${ctx_int}" -ge 50 ]]; then
    ctx_color="${YELLOW}"
  else
    ctx_color="${GREEN}"
  fi

  parts+=("${ctx_color}${bar}${ctx_int}%${RESET}")
fi

# 4. 세션 비용
if [[ -n "${cost_usd}" ]]; then
  cost_fmt=$(awk "BEGIN { printf \"%.2f\", ${cost_usd} }")
  parts+=("\$${cost_fmt}")
fi

# 5. 시간당 비용 (duration 60초 이상일 때만)
if [[ -n "${cost_usd}" && -n "${duration_ms}" ]]; then
  if [[ "${duration_ms}" -ge 60000 ]]; then
    hourly=$(awk "BEGIN { printf \"%.0f\", ${cost_usd} / (${duration_ms} / 3600000) }")
    parts+=("(\$${hourly}/h)")
  fi
fi

# 6. 누적 토큰
if [[ -n "${total_in}" || -n "${total_out}" ]]; then
  in_fmt=$(format_tokens "${total_in:-0}")
  out_fmt=$(format_tokens "${total_out:-0}")

  parts+=("in:${in_fmt} out:${out_fmt}")
fi

# 7. 캐시 히트율
if [[ -n "${cache_read}" && -n "${input_tokens}" ]]; then
  cache_total=$(( cache_read + input_tokens ))

  if [[ "${cache_total}" -gt 0 ]]; then
    cache_pct=$(awk "BEGIN { printf \"%.0f\", ${cache_read} / ${cache_total} * 100 }")
    parts+=("cache:${cache_pct}%")
  fi
fi

# 8. 코드 변경량
if [[ -n "${lines_added}" || -n "${lines_removed}" ]]; then
  change=""

  if [[ -n "${lines_added}" && "${lines_added}" != "0" ]]; then
    change+="${GREEN}+${lines_added}${RESET}"
  fi

  if [[ -n "${lines_removed}" && "${lines_removed}" != "0" ]]; then
    [[ -n "${change}" ]] && change+="/"
    change+="${RED}-${lines_removed}${RESET}"
  fi

  if [[ -n "${change}" ]]; then
    parts+=("${change}")
  fi
fi

# 9. 세션 경과 시간
if [[ -n "${duration_ms}" ]]; then
  dur_fmt=$(format_duration "${duration_ms}")
  parts+=("${dur_fmt}")
fi

# 10. 에이전트 이름 (agent 모드일 때만)
if [[ -n "${agent_name}" ]]; then
  parts+=("${CYAN}[${agent_name}]${RESET}")
fi

# 11. Vim 모드 (vim 활성일 때만)
if [[ -n "${vim_mode}" ]]; then
  parts+=("${MAGENTA}[${vim_mode}]${RESET}")
fi

# 12. 모델명
if [[ -n "${model}" ]]; then
  parts+=("${YELLOW}${model}${RESET}")
fi

# --- 최종 출력 ---
# ANSI reset 으로 Claude Code dim 스타일 재정의
output=$'\033[0m'

for (( i = 0; i < ${#parts[@]}; i++ )); do
  if [[ "${i}" -gt 0 ]]; then
    output+=" "
  fi

  output+="${parts[${i}]}"
done

# 공백을 non-breaking space 로 치환
nbsp=$'\xC2\xA0'
output="${output// /${nbsp}}"

printf '%s' "${output}"
