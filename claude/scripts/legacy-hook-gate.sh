#!/usr/bin/env bash
# 플러그인으로 옮긴 장치의 옛 훅을 넘겨주는 문 — legacy-hook-gate.sh <플러그인 이름> <옛 스크립트 파일 이름>
#
# 설정 파일에서 훅 블록을 지우면 이미 떠 있는 세션도 그 훅을 즉시 잃는데 (2.1.329 실측), 플러그인 훅은 세션 시작 때만 실린다.
# 그래서 블록을 지우지 않고 이 스크립트를 거치게 한다:
#   - 이 세션에 플러그인 훅이 실렸다는 표시 (플러그인의 SessionStart 훅이 남긴다. 내용은 플러그인 폴더 경로) 가 있으면 아무것도 하지 않는다 — 플러그인 훅이 맡는다
#   - 표시가 없거나 판단할 수 없으면 옛 스크립트를 그대로 실행한다 (두 번 도는 쪽이 꺼지는 쪽보다 낫다)
# 옮기기 전에 시작한 세션이 모두 닫히면 설정의 블록 · 이 스크립트 · 옛 스크립트를 함께 지운다.
set -uo pipefail

plugin_name="${1:-}"
legacy_script="$(dirname "${BASH_SOURCE[0]}")/${2:-}"
hook_input=$(cat)
session_id=$(jq -r '.session_id // empty' <<<"${hook_input}" 2>/dev/null)

marker="${TMPDIR:-/tmp}/claude-plugin-sessions/${plugin_name}-${session_id}"

if [[ -n "${plugin_name}" && "${session_id}" =~ ^[A-Za-z0-9_-]+$ && -f "${marker}" ]]; then
  plugin_root=$(head -1 "${marker}" 2>/dev/null)

  # 표시에 플러그인 폴더가 적혀 있으면 그 폴더에 같은 이름의 훅이 실제로 있을 때만 물러난다 (옛 버전 폴더가 지워진 세션에서 장치가 꺼지지 않게).
  # 내용이 빈 표시는 경로를 적기 전 버전의 플러그인이 남긴 것 — 그대로 물러난다
  if [[ -z "${plugin_root}" || -f "${plugin_root}/hooks/${2:-}" ]]; then
    exit 0
  fi
fi

exec bash "${legacy_script}" <<<"${hook_input}"
