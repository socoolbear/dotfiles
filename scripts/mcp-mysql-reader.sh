#!/usr/bin/env bash
# MySQL 읽기 전용 MCP 실행기. 비밀번호는 1Password(op://...) 또는 macOS 키체인에서 꺼낸다.
# 사용: mcp-mysql-reader <op://금고/항목/필드 | 키체인 항목명>  (MYSQL_HOST/PORT/USER/DB 는 env 로 전달)
set -euo pipefail

secretRef="${1:?op:// 참조 또는 키체인 항목명이 필요합니다}"

# op:// 참조는 지연 시작 프록시를 거친다 — 세션이 뜰 때가 아니라 첫 쿼리 때 1Password 를 부른다 (2026-11-19 사용자 결정)
if [[ "${secretRef}" == op://* && -z "${MCP_LAZY_CHILD:-}" ]]; then
  exec "${HOME}/.local/bin/mcp-lazy" "${0##*/} ${secretRef} ${MYSQL_HOST:-} ${MYSQL_DB:-}" -- "${0}" "$@"
fi

readSecret() {
  if [[ "${1}" == op://* ]]; then
    op read "${1}"
  else
    security find-generic-password -s "${1}" -w
  fi
}

mysqlPass="$(readSecret "${secretRef}")"

export MYSQL_PASS="${mysqlPass}"
export ALLOW_INSERT_OPERATION=false
export ALLOW_UPDATE_OPERATION=false
export ALLOW_DELETE_OPERATION=false
export ALLOW_DDL_OPERATION=false

exec npx -y @benborla29/mcp-server-mysql
