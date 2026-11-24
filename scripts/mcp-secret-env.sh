#!/usr/bin/env bash
# MCP 서버 실행기: 비밀 값을 1Password(op://...) 또는 macOS 키체인에서 꺼내 환경 변수 하나로 넘기고 서버 명령을 실행한다.
# 설정 파일 (~/.claude.json) 에 비밀번호를 평문으로 두지 않으려는 것이다. 읽기 전용 여부는 서버 쪽 설정이 정한다.
# 사용: mcp-secret-env <환경 변수 이름> <op://금고/항목/필드 | 키체인 항목명> -- <서버 명령> [인자...]
#       mcp-secret-env --sweep   (보관 시간이 지난 키체인 사본을 지운다 — launchd 가 1시간마다 부른다)
set -euo pipefail

# op:// 로 꺼낸 값은 로그인 키체인에 8시간 보관해 다시 쓴다 (2026-11-24 사용자 결정 — 써 보고 유지 여부를 정한다).
# 터미널 없는 프로세스 (Claude 의 Bash 호출 등) 는 op 를 부를 때마다 1Password 승인 창이 새로 뜨기 때문이다.
# 키체인에는 만료 기능이 없어, 지난 사본은 --sweep (launchd 1시간마다) 이 지운다. 그래서 사본은 길어야 9시간 남는다.
# 보관 항목의 서비스 이름은 "mcp-secret-env <op:// 참조>". 1Password 쪽 값을 바꿨으면 security delete-generic-password -s "<그 이름>" 으로 지운다
CACHE_SECONDS=28800
CACHE_PREFIX="mcp-secret-env "

isFreshCache() {
  local service="${1}"
  local attributes savedAt

  attributes="$(security find-generic-password -s "${service}" 2>/dev/null)" || return 1
  savedAt="$(sed -n 's/.*"icmt"<blob>="\([0-9]*\)".*/\1/p' <<< "${attributes}")"

  [[ -n "${savedAt}" ]] && (( $(date +%s) - savedAt < CACHE_SECONDS ))
}

sweepExpiredCaches() {
  local service

  # dump-keychain 은 비밀값 없이 속성만 내보낸다 (-d 를 주지 않음)
  security dump-keychain 2>/dev/null \
    | sed -n "s/.*\"svce\"<blob>=\"\(${CACHE_PREFIX}op:[^\"]*\)\".*/\1/p" \
    | sort -u \
    | while IFS= read -r service; do
        if ! isFreshCache "${service}"; then
          security delete-generic-password -s "${service}" >/dev/null 2>&1 || true
        fi
      done
}

readOpSecret() {
  local ref="${1}"
  local service="${CACHE_PREFIX}${ref}"
  local value

  if isFreshCache "${service}"; then
    value="$(security find-generic-password -s "${service}" -w 2>/dev/null)" || value=""

    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return
    fi
  fi

  # 이 함수는 $(...) 안에서 돌아 set -e 가 듣지 않는다 — 승인을 취소해 op 가 실패하거나 빈 값이면 보관하지 않고 실패로 끝낸다
  value="$(op read "${ref}")" || return 1

  if [[ -z "${value}" ]]; then
    echo "${0##*/}: ${ref} 의 값이 비어 있습니다" >&2
    return 1
  fi

  saveCache "${service}" "${value}"
  printf '%s\n' "${value}"
}

# 값은 명령줄 인자가 아니라 security -i 의 표준 입력으로 넘긴다 (ps 에 보이지 않게).
# add-generic-password -w 를 값 없이 쓰면 터미널이 붙은 프로세스 (Claude 세션이 띄운 MCP 서버) 에서 표준 입력이 아니라 터미널에 입력을 묻고 멈춘다
saveCache() {
  local service="${1}"
  local value="${2}"
  local escaped

  escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf 'add-generic-password -U -s "%s" -a "%s" -j "%s" -w "%s"\n' "${service}" "${USER}" "$(date +%s)" "${escaped}" \
    | security -i >/dev/null 2>&1 || true
}

readSecret() {
  if [[ "${1}" == op://* ]]; then
    readOpSecret "${1}"
  else
    security find-generic-password -s "${1}" -w
  fi
}

if [[ "${1:-}" == "--sweep" ]]; then
  sweepExpiredCaches
  exit 0
fi

envName="${1:?환경 변수 이름이 필요합니다}"
secretRef="${2:?op:// 참조 또는 키체인 항목명이 필요합니다}"

if [[ "${3:-}" != "--" || $# -lt 4 ]]; then
  echo "사용: ${0##*/} <환경 변수 이름> <op://… | 키체인 항목명> -- <서버 명령> [인자...]" >&2
  exit 2
fi

# op:// 참조는 지연 시작 프록시를 거친다 — 세션이 뜰 때가 아니라 첫 쿼리 때 1Password 를 부른다 (2026-11-19 사용자 결정)
if [[ "${secretRef}" == op://* && -z "${MCP_LAZY_CHILD:-}" ]]; then
  exec "${HOME}/.local/bin/mcp-lazy" "${0##*/} ${secretRef} ${*:4}" -- "${0}" "$@"
fi

secretValue="$(readSecret "${secretRef}")"

export "${envName}=${secretValue}"

exec "${@:4}"
