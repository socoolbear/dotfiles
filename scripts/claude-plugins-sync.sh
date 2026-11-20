#!/usr/bin/env bash
#
# make sync 가 부른다 — Claude Code 플러그인을 이 장비에 맞춘다.
#
#   1. 설치: 공용 settings.json 의 enabledPlugins 에서 켠 마켓플레이스 플러그인 중 이 장비에 설치 기록이 없는 것을 설치한다.
#      플러그인 이름은 여기 적지 않고 settings.json 에서 읽는다. 이미 있으면 건너뛴다 (여러 번 돌려도 결과가 같다)
#   2. 장비 등록: 설치만으로 끝나지 않는 장치 (launchd 예약 · 고정 경로 실행 파일) 를 다시 건다.
#      장비 설정 파일이 있을 때만 실행하고, 없으면 실행할 명령을 안내한다 (장비마다 다른 값은 여기 넣지 않는다)
#
# `claude` 나 `jq` 가 없으면 (make fresh 초반) 건너뛰고 안내한다.
#   CLAUDE_PLUGINS_SYNC_DRY=1   할 일만 출력

set -euo pipefail

readonly SETTINGS="${HOME}/.claude/settings.json"
readonly INSTALLED="${CLAUDE_PLUGINS_INSTALLED_FILE:-${HOME}/.claude/plugins/installed_plugins.json}"
readonly DRY="${CLAUDE_PLUGINS_SYNC_DRY:-}"

# 켜져 있는데 설치 기록이 없는 플러그인 (builtin 은 Claude Code 에 들어 있어 설치 대상이 아니다)
listMissingPlugins() {
  local installed='{"plugins":{}}'

  [[ -f "${INSTALLED}" ]] && installed=$(cat "${INSTALLED}")

  jq -r --argjson installed "${installed}" '
    .enabledPlugins // {}
    | to_entries[]
    | select(.value == true and (.key | endswith("@builtin") | not))
    | .key
    | select(($installed.plugins // {})[.] == null)' "${SETTINGS}"
}

# `claude plugin install` 은 settings.json 을 다시 쓰면서 키 순서를 바꾼다. 내용이 같으면 원래 글로 되돌려
# 심링크 대상인 dotfiles 작업 트리가 더러워지지 않게 한다
installMissingPlugins() {
  local missing plugin backup

  missing=$(listMissingPlugins)

  if [[ -z "${missing}" ]]; then
    return 0
  fi

  if [[ -n "${DRY}" ]]; then
    sed 's/^/[dry] 플러그인 설치 예정: /' <<<"${missing}"
    return 0
  fi

  backup=$(mktemp)
  cp "${SETTINGS}" "${backup}"

  while IFS= read -r plugin; do
    if claude plugin install "${plugin}" </dev/null >/dev/null 2>&1; then
      echo "==> Claude 플러그인 설치: ${plugin}"
    else
      echo "==> Claude 플러그인 설치 실패: ${plugin} (세션에서 /plugin install ${plugin})"
    fi
  done <<<"${missing}"

  if [[ "$(jq -S . "${backup}")" == "$(jq -S . "${SETTINGS}")" ]]; then
    cat "${backup}" >"${SETTINGS}"
  fi

  rm -f "${backup}"
}

installedPath() {   # installedPath <플러그인 이름> → 설치본 폴더 (없으면 빈 값)
  [[ -f "${INSTALLED}" ]] || return 0
  jq -r --arg prefix "$1@" '[.plugins | to_entries[] | select(.key | startswith($prefix)) | .value[] | .installPath] | last // empty' "${INSTALLED}"
}

# workstyle: ~/.local/bin/workstyle · loop-metrics 실행 파일 (설치본을 찾아 부르는 작은 스크립트)
registerWorkstyle() {
  local root runner

  root=$(installedPath workstyle)
  runner="${root}/bin/workstyle"

  [[ -n "${root}" && -x "${runner}" ]] || return 0

  if [[ -n "${DRY}" ]]; then
    echo "[dry] ${runner} install"
    return 0
  fi

  "${runner}" install >/dev/null || echo "==> workstyle 실행 파일 등록 실패 — 직접 실행해 확인: ${runner} install"

  # 취향 규칙 폴더는 세션 시작 훅이 사본을 만든다. 전역 지시 파일의 불러오기 줄과 개발 장비 심링크는 /workstyle:setup 이 맡는다
  if [[ ! -e "${HOME}/.claude/workstyle" ]]; then
    echo "==> 취향 규칙 폴더 (~/.claude/workstyle) 가 없습니다 — 세션에서 /workstyle:setup"
  fi
}

main() {
  if ! command -v claude >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "==> claude 또는 jq 가 없어 Claude 플러그인 맞추기를 건너뜁니다 — 설치 뒤 make sync 를 다시 실행하세요"
    return 0
  fi

  if [[ ! -f "${SETTINGS}" ]]; then
    return 0
  fi

  installMissingPlugins
  registerWorkstyle
}

main "$@"
