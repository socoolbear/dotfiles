#!/usr/bin/env bash
# MCP 서버 실행기: 비밀 값을 1Password(op://...) 또는 macOS 키체인에서 꺼내 환경 변수 하나로 넘기고 서버 명령을 실행한다.
# 설정 파일 (~/.claude.json) 에 비밀번호를 평문으로 두지 않으려는 것이다. 읽기 전용 여부는 서버 쪽 설정이 정한다.
# 사용: mcp-secret-env <환경 변수 이름> <op://금고/항목/필드 | 키체인 항목명> -- <서버 명령> [인자...]
set -euo pipefail

envName="${1:?환경 변수 이름이 필요합니다}"
secretRef="${2:?op:// 참조 또는 키체인 항목명이 필요합니다}"

if [[ "${3:-}" != "--" || $# -lt 4 ]]; then
  echo "사용: ${0##*/} <환경 변수 이름> <op://… | 키체인 항목명> -- <서버 명령> [인자...]" >&2
  exit 2
fi

# op:// 참조는 지연 시작 프록시를 거친다 — 세션이 뜰 때가 아니라 첫 쿼리 때 1Password 를 부른다 (mcp-*-reader 와 같은 방식)
if [[ "${secretRef}" == op://* && -z "${MCP_LAZY_CHILD:-}" ]]; then
  exec "${HOME}/.local/bin/mcp-lazy" "${0##*/} ${secretRef} ${*:4}" -- "${0}" "$@"
fi

readSecret() {
  if [[ "${1}" == op://* ]]; then
    op read "${1}"
  else
    security find-generic-password -s "${1}" -w
  fi
}

secretValue="$(readSecret "${secretRef}")"

export "${envName}=${secretValue}"

exec "${@:4}"
