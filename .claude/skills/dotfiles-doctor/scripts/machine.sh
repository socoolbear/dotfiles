#!/usr/bin/env bash
# 이 장비의 상태 점검 — 읽기 전용. 아무것도 고치지 않는다 (저장소 밖 파일이라 doctor 가 고치지 않고 보고만 한다).
# 출력: doctor.sh 와 같은 형식 — [FAIL] 확실한 결함 / [WARN] 판단할 것 / [INFO] 판단 재료. FAIL 이 하나라도 있으면 exit 1.
# 비밀값은 출력하지 않는다 (서버 이름 · env 키 이름 · 파일 이름만).
#
# MACHINE_HOME 으로 홈을 바꿀 수 있다 (가짜 HOME 시험용). launchctl · npm 은 바꾸지 않고 그대로 부른다.
# set -e 를 쓰지 않는 이유: 점검 하나가 실패해도 나머지 점검을 끝까지 돌려야 한다.
set -uo pipefail

H="${MACHINE_HOME:-${HOME}}"
DOTFILES="${DOTFILES:-${HOME}/.dotfiles}"
CLAUDE_JSON="${H}/.claude.json"
PLUGINS_DIR="${H}/.claude/plugins"
ALLOW_FILE="${H}/.config/dotfiles/mcp-plaintext-allow"
BREW_LOG="${H}/Library/Logs/brew-scheduled-update.log"
MAIL_FAILED_FLAG="${H}/.local/state/dotfiles-machine-check/mail-failed"
UPDATE_STATUS="${H}/.local/state/dotfiles-update/status"
UPDATE_STALE_DAYS=3
GUARD_LOGS="${H}/.cc-safety-net/logs"
BACKUP_DIR="${H}/backup_dotfiles"
NOW=$(date +%s)
fail_count=0
tilde="~"   # 경로 표시용. ${x/#${HOME}/~} 처럼 ~ 를 바로 쓰면 bash 5.x 는 홈 경로로 다시 풀어 버린다

fail() { printf '[FAIL] %s\n' "$*"; fail_count=$(( fail_count + 1 )); }
warn() { printf '[WARN] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

# 네트워크 명령이 멈춰 점검 전체가 서지 않게 한다 (timeout 이 없는 장비는 제한 없이)
run_limited() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 20 "$@"
  else
    "$@"
  fi
}

# --- 0. 점검에 쓰는 명령 ---
# launchd 예약 실행처럼 PATH 가 짧은 곳에서 명령을 못 찾으면, 그 명령을 쓰는 점검이 조용히 0건으로 끝난다.
# 모두 Brewfile · mise 가 까는 명령이라 없으면 설치나 PATH 를 볼 일이다.
echo "## 0. 점검에 쓰는 명령"

for required in jq git gh npm node; do
  command -v "${required}" >/dev/null 2>&1 || warn "명령 없음: ${required} — 이 명령을 쓰는 점검이 빠진다 (설치 · PATH 확인)"
done

# --- 1. MCP 설정의 평문 비밀값 ---
# 전역 · 프로젝트별 mcpServers 를 본다. 판정: 접속 문자열 안의 비밀번호 · URL 쿼리의 토큰 · 비밀 이름의 env/header 값이 1Password 참조 (op://) 나 ${…} 참조가 아닌 것.
# 예외는 저장소 밖 목록 (서버:키 한 줄씩) — 서버 이름을 공개 저장소에 넣지 않는다.
echo "## 1. MCP 평문 비밀값"

mcp_plaintext_hits() {
  jq -r '
    def secret_name: test("PASS|TOKEN|SECRET|KEY|AUTH"; "i");
    def url_secret: type == "string" and (
      test("[a-z][a-z0-9+.-]*://[^/@\\s:]+:[^/@\\s]+@"; "i")
      or test("[?&](token|key|api_key|apikey|access_token|password|secret)=[^&\\s]+"; "i"));
    def flag_secret: type == "string" and test("^--?[a-z0-9_-]*(pass|token|secret|key)[a-z0-9_-]*=.+"; "i") and (test("=op://") | not);
    def reference_only: test("\\$\\{") and (test("\\$\\{[^}:]*:-[^}]+\\}") | not);
    def plain_value: type == "string" and length > 0 and (startswith("op://") | not) and (reference_only | not);
    def servers: (.mcpServers // {} | to_entries[]), (.projects // {} | to_entries[] | .value.mcpServers // {} | to_entries[]);
    servers | .key as $name | .value as $server
    | ( ($server.args // [] | to_entries[] | select((.value | url_secret) or (.value | flag_secret)) | "\($name)\targs[\(.key)]"),
        (if ($server.url // "" | url_secret) then "\($name)\turl" else empty end),
        ($server.env // {}, $server.headers // {} | to_entries[]
          | select(((.key | secret_name) and (.value | plain_value)) or (.value | url_secret)) | "\($name)\t\(.key)") )
  ' "${CLAUDE_JSON}" 2>/dev/null | sort -u
}

if [[ ! -f "${CLAUDE_JSON}" ]]; then
  info "MCP 설정 파일 없음 — 건너뜀"
else
  allowed=$( [[ -f "${ALLOW_FILE}" ]] && grep -vE '^[[:space:]]*(#|$)' "${ALLOW_FILE}" )
  skipped=0

  while IFS=$'\t' read -r server key; do
    [[ -n "${server}" ]] || continue

    if grep -qxF "${server}:${key}" <<< "${allowed}"; then
      skipped=$(( skipped + 1 ))
      continue
    fi

    fail "MCP 평문 비밀값: ${server} (${key}) — 1Password 참조 (op://) 로 바꾸거나, 의도한 값이면 ${ALLOW_FILE/#${HOME}/${tilde}} 에 '${server}:${key}'"
  done < <(mcp_plaintext_hits)

  (( skipped == 0 )) || info "MCP 평문 비밀값: 예외 목록으로 건너뜀 ${skipped}건"
fi

# --- 2. 폐기된 MCP 패키지 ---
# npx 로 띄우는 패키지와, 래퍼 스크립트 안에서 npx 로 띄우는 패키지의 npm 폐기 표시를 본다.
# 패키지 이름 꼴을 통과한 값만 npm 에 묻는다 (인자를 잘못 뽑아 비밀값이 바깥으로 나가지 않게).
echo "## 2. 폐기된 MCP 패키지"

PACKAGE_RE='^(@[a-z0-9._-]+/)?[a-z0-9._-]+(@[A-Za-z0-9._^~<>=-]+)?$'

mcp_packages() {
  jq -r '
    def package_after_npx:
      . as $words
      | ([range(0; length)] | map(select($words[.] | test("(^|/)npx$"))) | first) as $i
      | if $i == null then empty else
          ($words[$i + 1:] | reduce .[] as $word ({skip: false, found: null};
            if .found then .
            elif .skip then .skip = false
            elif ($word | test("^(-p|--package|--registry|--cache|-c|--call|--userconfig)$")) then .skip = true
            elif ($word | startswith("-")) then .
            else .found = $word end) | .found // empty)
        end;
    (.mcpServers // {} | to_entries[]), (.projects // {} | to_entries[] | .value.mcpServers // {} | to_entries[])
    | .value | select(.command != null)
    | ([.command] + (.args // []) | package_after_npx | "npx\t\(.)"), "command\t\(.command)"
  ' "${CLAUDE_JSON}" 2>/dev/null
}

# 래퍼 스크립트 (텍스트 파일) 안의 `npx [-y] <패키지>`
packages_in_wrapper() {
  local command_path="${1/#\~/${HOME}}"

  [[ "${command_path}" == /* && -f "${command_path}" ]] || return 0
  file -bL --mime-type "${command_path}" | grep -q '^text/' || return 0

  grep -oE 'npx( +(-y|--yes))* +[@A-Za-z0-9._/^~<>=-]+' "${command_path}" | awk '{ print $NF }'
}

if [[ ! -f "${CLAUDE_JSON}" ]]; then
  info "MCP 설정 파일 없음 — 건너뜀"
elif ! command -v npm >/dev/null 2>&1; then
  info "npm 없음 — 폐기 표시 확인 불가"
else
  packages=$(
    while IFS=$'\t' read -r kind value; do
      # $( ) 안의 case 는 패턴 앞에 ( 를 붙여야 bash 3.2 가 괄호 짝을 맞게 읽는다
      case "${kind}" in
        (npx) printf '%s\n' "${value}" ;;
        (command) packages_in_wrapper "${value}" ;;
      esac
    done < <(mcp_packages) | grep -E "${PACKAGE_RE}" | sort -u
  )

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue

    if ! deprecated=$(run_limited npm view "${package}" deprecated 2>/dev/null); then
      info "폐기 표시 확인 불가: ${package} (오프라인이거나 npm 오류)"
      continue
    fi

    [[ -z "${deprecated}" ]] || warn "폐기된 MCP 패키지: ${package} — ${deprecated:0:120}"
  done <<< "${packages}"
fi

# --- 3. 플러그인 정합 ---
# 켜 둔 목록 (settings.json enabledPlugins) · 마켓플레이스 목록 · 설치 목록 · 캐시를 대조한다.
# 같은 플러그인의 옛 버전 폴더는 Claude Code 가 .orphaned_at 표시로 관리하므로 보지 않는다.
echo "## 3. 플러그인 정합"

settings="${H}/.claude/settings.json"
known="${PLUGINS_DIR}/known_marketplaces.json"
installed="${PLUGINS_DIR}/installed_plugins.json"

marketplace_manifest() {
  local location

  location=$(jq -r --arg m "${1}" '.[$m].installLocation // empty' "${known}")
  [[ -n "${location}" && -d "${location}" ]] || location="${PLUGINS_DIR}/marketplaces/${1}"
  printf '%s/.claude-plugin/marketplace.json' "${location}"
}

if [[ ! -f "${settings}" || ! -f "${known}" || ! -f "${installed}" ]]; then
  info "settings · 마켓플레이스 · 설치 목록 중 없는 파일이 있음 — 건너뜀 (새 장비면 make sync 뒤 다시)"
else
  installed_keys=$(jq -r '.plugins // {} | keys[]' "${installed}")

  while IFS=$'\t' read -r key enabled; do
    plugin="${key%@*}"
    market="${key##*@}"
    [[ "${market}" == builtin || "${enabled}" != true ]] && continue

    if ! jq -e --arg m "${market}" 'has($m)' "${known}" >/dev/null; then
      fail "켜 둔 플러그인의 마켓플레이스가 등록되지 않음: ${key}"
      continue
    fi

    manifest=$(marketplace_manifest "${market}")

    if [[ ! -f "${manifest}" ]]; then
      warn "마켓플레이스 목록 파일 없음: ${market} (${key} 를 확인하지 못함)"
    elif ! jq -e --arg p "${plugin}" '.plugins | any(.name == $p)' "${manifest}" >/dev/null; then
      fail "켜 둔 플러그인이 마켓플레이스 목록에 없음: ${key} — 지워졌거나 이름이 바뀜 (settings.json 의 줄을 정리)"
      continue
    fi

    grep -qxF "${key}" <<< "${installed_keys}" || warn "켜 뒀는데 설치되지 않음: ${key} (make sync)"
  done < <(jq -r '.enabledPlugins // {} | to_entries[] | "\(.key)\t\(.value)"' "${settings}")

  while IFS= read -r key; do
    jq -e --arg k "${key}" '.enabledPlugins // {} | has($k)' "${settings}" >/dev/null \
      || warn "설치됐는데 settings.json enabledPlugins 에 줄이 없음: ${key}"
  done <<< "${installed_keys}"

  # 설치 목록에 없는 플러그인의 캐시 폴더: 모든 버전에 표시가 있고 가장 늦은 표시가 7일 넘었으면 Claude Code 가 지우지 못한 것
  for plugin_dir in "${PLUGINS_DIR}"/cache/*/*/; do
    [[ -d "${plugin_dir}" ]] || continue
    plugin=$(basename "${plugin_dir}")
    market=$(basename "$(dirname "${plugin_dir}")")
    grep -qxF "${plugin}@${market}" <<< "${installed_keys}" && continue

    latest_ms=0
    unmarked=0

    for version_dir in "${plugin_dir}"*/; do
      [[ -d "${version_dir}" ]] || continue

      if [[ -f "${version_dir}.orphaned_at" ]]; then
        marked_ms=$(tr -cd '0-9' < "${version_dir}.orphaned_at")
        (( ${marked_ms:-0} > latest_ms )) && latest_ms=${marked_ms}
      else
        unmarked=$(( unmarked + 1 ))
      fi
    done

    (( unmarked == 0 && latest_ms > 0 )) || continue
    age_days=$(( (NOW - latest_ms / 1000) / 86400 ))
    (( age_days >= 7 )) && warn "지워지지 않은 플러그인 캐시: ${plugin_dir/#${HOME}/${tilde}} (설치 목록에 없음, 정리 대상 표시 ${age_days}일 전)"
  done
fi

# --- 4. 예약 작업 ---
# dotfiles 의 launchd 작업이 등록돼 있는가, Homebrew 예약 갱신이 최근 48시간 안에 돌았고 오래 걸리거나 실패하지 않았는가,
# dotfiles 자동 갱신이 며칠째 돌지 않았거나 손 필요 · 실패가 며칠째 이어지지 않는가.
echo "## 4. 예약 작업"

for plist in "${DOTFILES}"/launchd/*.plist; do
  [[ -f "${plist}" ]] || continue
  label=$(plutil -extract Label raw "${plist}" 2>/dev/null)
  [[ -n "${label}" ]] || { warn "launchd Label 을 읽지 못함: ${plist##*/}"; continue; }
  launchctl list "${label}" >/dev/null 2>&1 || fail "launchd 작업이 등록되지 않음: ${label} (make sync)"
done

log_epoch() { date -j -f '%Y-%m-%d %H:%M:%S' "${1}" +%s 2>/dev/null; }

if [[ ! -f "${BREW_LOG}" ]]; then
  info "Homebrew 예약 갱신 로그 없음 — 건너뜀"
else
  # 실행 단위: '===== 시작' ~ '===== 완료', 그 사이의 '결과:' 줄 (2026-11-21 형식부터 있음)
  runs=$(grep -E '^[0-9-]{10} [0-9:]{8} (===== (시작|완료) =====|결과: )' "${BREW_LOG}" | awk '
    { stamp = $1 " " $2 }
    / ===== 시작 =====/ { if (start != "") print start "\t" end "\t" result; start = stamp; end = ""; result = ""; next }
    / ===== 완료 =====/ { end = stamp; next }
    / 결과: / { sub(/^[^ ]+ [^ ]+ 결과: /, ""); result = $0 }
    END { if (start != "") print start "\t" end "\t" result }
  ')
  recent=0
  failed_streak=0

  while IFS=$'\t' read -r started ended result; do
    [[ -n "${started}" ]] || continue
    start_epoch=$(log_epoch "${started}")
    [[ -n "${start_epoch}" ]] || continue

    if [[ -n "${result}" ]]; then
      if [[ "${result}" == "실패한 단계 없음" ]]; then
        failed_streak=0
      else
        failed_streak=$(( failed_streak + 1 ))
      fi
    fi

    (( NOW - start_epoch <= 48 * 3600 )) || continue
    recent=$(( recent + 1 ))

    if [[ -z "${ended}" ]]; then
      (( NOW - start_epoch > 2 * 3600 )) && warn "Homebrew 예약 갱신: ${started} 시작 뒤 완료 기록 없음 (2시간 넘음)"
      continue
    fi

    minutes=$(( ($(log_epoch "${ended}") - start_epoch) / 60 ))
    (( minutes > 30 )) && warn "Homebrew 예약 갱신: ${started} 실행이 ${minutes}분 걸림 (잠자기로 멈췄을 수 있음 — 로그 확인)"

    if [[ -n "${result}" && "${result}" != "실패한 단계 없음" ]]; then
      if (( failed_streak >= 2 )); then
        fail "Homebrew 예약 갱신: ${started} 실행까지 ${failed_streak}번 연속 실패 — ${result:0:120}"
      else
        warn "Homebrew 예약 갱신: ${started} 실행 실패 — ${result:0:120}"
      fi
    fi
  done <<< "${runs}"

  (( recent > 0 )) || warn "Homebrew 예약 갱신: 최근 48시간 안에 실행 기록 없음 (launchd 작업 · 로그 확인)"
fi

# dotfiles 자동 갱신 (scripts/dotfiles-auto-update.sh) 이 남긴 상태 파일. 메뉴 막대를 못 본 채 지나간 것을 주 1회 메일로 잡는다
if [[ ! -f "${UPDATE_STATUS}" ]]; then
  info "dotfiles 자동 갱신: 상태 파일 없음 — 아직 한 번도 돌지 않음 (make auto-update)"
else
  last_update=$(awk -F'\t' '$1 == "last_run" { print $3 }' "${UPDATE_STATUS}")
  update_days=$(( (NOW - ${last_update:-0}) / 86400 ))
  (( update_days > UPDATE_STALE_DAYS )) && warn "dotfiles 자동 갱신: ${update_days}일 넘게 돌지 않음 (make auto-update-log · launchd 작업 확인)"

  while IFS=$'\t' read -r target state detail since; do
    case "${state}" in
      (manual) label="손 필요" ;;
      (failed) label="실패" ;;
      (unreachable) label="받아오지 못함" ;;
      (*) continue ;;
    esac

    stuck_days=$(( (NOW - ${since:-${NOW}}) / 86400 ))

    if (( stuck_days > UPDATE_STALE_DAYS )); then
      warn "dotfiles 자동 갱신: ${target} — ${label} ${stuck_days}일째 (${detail:0:120})"
    else
      info "dotfiles 자동 갱신: ${target} — ${label} (${detail:0:120})"
    fi
  done < <(grep -v '^last_run' "${UPDATE_STATUS}")
fi

# 주 1회 장비 점검은 결과를 메일로만 알린다. 메일을 못 보냈으면 그 스크립트가 남긴 표시 파일을 여기서 WARN 으로 올린다 (조용히 묻히지 않게)
if [[ -f "${MAIL_FAILED_FLAG}" ]]; then
  warn "지난 장비 점검이 결과를 메일로 알리지 못함: $(head -c 200 "${MAIL_FAILED_FLAG}") — 로그 (make machine-check-log) 확인, 다음 발송이 성공하면 사라진다"
fi

# --- 5. 파괴적 명령 가드 (판단 재료) ---
# 차단이 평소 일을 막았는지는 사람이 판정한다 (claude/Readme.md 「파괴적 명령 가드」). 여기서는 건수만 낸다.
echo "## 5. 파괴적 명령 가드"

if [[ ! -d "${GUARD_LOGS}" ]]; then
  info "가드 기록 없음 — 건너뜀"
else
  cutoff=$(date -u -v-7d +%Y-%m-%dT%H:%M)
  denied_rules=$(find "${GUARD_LOGS}" -name '*.jsonl' -mtime -8 -print0 2>/dev/null \
    | xargs -0 cat 2>/dev/null \
    | jq -r --arg cutoff "${cutoff}" 'select(.decision == "deny" and (.ts // "") >= $cutoff and ((.cwd // "") | test("/scratchpad/") | not)) | .ruleId // "?"' 2>/dev/null)
  denied_count=$(grep -c . <<< "${denied_rules}")
  top_rules=$(grep . <<< "${denied_rules}" | sort | uniq -c | sort -rn | head -3 | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')
  info "가드 최근 7일 차단 ${denied_count}건 (scratchpad 제외)${top_rules:+ — ${top_rules}}"
fi

# --- 6. 비밀값이 든 사본 ---
# MCP 설정 사본 (claude-json-*) 은 비밀값을 담는다. 내용은 읽지 않고 이름과 일수만 본다.
echo "## 6. 비밀값 사본"

if [[ -d "${BACKUP_DIR}" ]]; then
  while IFS= read -r copy; do
    age_days=$(( (NOW - $(stat -f %m "${copy}")) / 86400 ))
    warn "오래된 비밀값 사본: ${copy/#${HOME}/${tilde}} (${age_days}일) — 쓸 일이 끝났으면 지울 것"
  done < <(find "${BACKUP_DIR}" -maxdepth 1 -name 'claude-json-*' -mtime +7)
fi

# --- 7. cc-marketplace 점검 (요약) ---
# 규칙 폴더 ~/.claude/workstyle 이 체크아웃을 가리키는 심링크일 때만 그 저장소의 health.sh 를 부른다 (옵션 없이 — 시험을 돌리지 않는 정적 점검).
# 고칠 것은 그 저장소의 evolve 로 한다. 이 점검은 고치지 않는다.
echo "## 7. cc-marketplace"

rules_link="${H}/.claude/workstyle"
marketplace_root=""
[[ -L "${rules_link}" ]] && marketplace_root=$(git -C "$(readlink "${rules_link}")" rev-parse --show-toplevel 2>/dev/null)

if [[ -z "${marketplace_root}" || ! -f "${marketplace_root}/scripts/health.sh" ]]; then
  info "cc-marketplace 체크아웃 (또는 scripts/health.sh) 없음 — 건너뜀"
else
  while IFS= read -r line; do
    case "${line}" in
      "[FAIL] "*) fail "cc-marketplace: ${line#\[FAIL\] }" ;;
      "[WARN] "*) warn "cc-marketplace: ${line#\[WARN\] }" ;;
      "[INFO] "*) info "cc-marketplace: ${line#\[INFO\] }" ;;
    esac
  done < <(bash "${marketplace_root}/scripts/health.sh" 2>&1)

  info "cc-marketplace 의 항목은 그 저장소에서 evolve 로 고친다 (${marketplace_root/#${HOME}/${tilde}})"
fi

echo
echo "FAIL ${fail_count}건"
(( fail_count == 0 ))
