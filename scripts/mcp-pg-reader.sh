#!/usr/bin/env bash
# PostgreSQL 읽기 전용 MCP 실행기 (server-postgres 는 모든 쿼리를 READ ONLY 트랜잭션으로 실행).
# 비밀번호는 1Password(op://...) 또는 macOS 키체인에서 꺼낸다.
# 사용: mcp-pg-reader <op://금고/항목/필드 | 키체인 항목명>  (PG_HOST/PG_PORT/PG_USER/PG_DB 는 env 로 전달)
set -euo pipefail

secretRef="${1:?op:// 참조 또는 키체인 항목명이 필요합니다}"

readSecret() {
  if [[ "${1}" == op://* ]]; then
    op read "${1}"
  else
    security find-generic-password -s "${1}" -w
  fi
}

encodedPass="$(readSecret "${secretRef}" \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(encodeURIComponent(s.trim())))')"

exec npx -y @modelcontextprotocol/server-postgres \
  "postgresql://${PG_USER}:${encodedPass}@${PG_HOST}:${PG_PORT}/${PG_DB}"
