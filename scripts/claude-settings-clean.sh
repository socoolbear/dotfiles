#!/usr/bin/env bash
# git 필터 — claude/settings.json 의 비공개 항목을 저장소에 넣지 않고 이 장비에만 남긴다.
#   clean  (커밋·add 때): 비공개 항목을 빼고 넘긴다. 뺀 항목은 이 장비의 보관 파일에 적는다.
#   smudge (pull·checkout 때): 저장소 내용에 보관 파일의 비공개 항목을 다시 합친다.
# 외부 도구 (setup 명령 등) 가 settings.json 에 직접 넣는 회사 전용 훅·권한 규칙을 공개 저장소에 올리지 않으려는 것.
# smudge 가 없으면 다른 장비에서 settings.json 을 고쳐 push 한 뒤 pull 할 때 이 장비의 비공개 항목이 지워진다.
#
# 뺄 낱말 목록: ~/.config/claude/settings-private-patterns (한 줄에 하나, # 은 주석). 비공개 파일이라 이 저장소에 두지 않는다.
# 낱말이 든 hooks 묶음 (그 묶음의 command 중 하나라도) 과 permissions.allow·ask·deny 항목이 대상이다.
# 보관 파일: ~/.local/state/claude-settings-private/private.json. 낱말 목록이 없으면 두 방향 모두 그대로 넘긴다.
# 연결: Makefile sync 가 filter.claude-private 를 설정하고 .gitattributes 가 claude/settings.json 에 건다.
set -euo pipefail

MODE="${1:?clean 또는 smudge}"
PATTERNS_FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/settings-private-patterns"
STASH_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-settings-private"
STASH_FILE="${STASH_DIR}/private.json"

if [[ ! -f "${PATTERNS_FILE}" ]]; then
  exec cat
fi

patterns=$(grep -v '^[[:space:]]*\(#\|$\)' "${PATTERNS_FILE}" | jq -R . | jq -sc .)

cleanSettings() {
  local input
  local private

  input=$(cat)
  private=$(jq --argjson patterns "${patterns}" '
    def private: . as $text | any($patterns[]; . as $pattern | $text | contains($pattern));
    {
      hooks: ((.hooks // {}) | with_entries(.value |= [ .[] | select(any(.hooks[]?; (.command // "") | private)) ]) | with_entries(select((.value | length) > 0))),
      permissions: ((.permissions // {}) | with_entries(select(.key | IN("allow", "ask", "deny"))) | with_entries(.value |= [ .[] | select(private) ]) | with_entries(select((.value | length) > 0)))
    }
  ' <<< "${input}")

  mkdir -p "${STASH_DIR}"
  printf '%s\n' "${private}" > "${STASH_FILE}.tmp"
  mv "${STASH_FILE}.tmp" "${STASH_FILE}"

  jq --indent 2 --argjson patterns "${patterns}" '
    def private: . as $text | any($patterns[]; . as $pattern | $text | contains($pattern));

    (if (.hooks | type) == "object" then
      .hooks |= with_entries(
        .value as $groups
        | .value |= [ .[] | select(any(.hooks[]?; (.command // "") | private) | not) ]
        | select((.value | length) > 0 or ($groups | length) == 0)
      )
    else . end)
    | (if (.permissions | type) == "object" then
      .permissions |= with_entries(
        if (.key | IN("allow", "ask", "deny")) and (.value | type) == "array" then
          .value as $rules
          | .value |= [ .[] | select(private | not) ]
          | select((.value | length) > 0 or ($rules | length) == 0)
        else . end
      )
    else . end)
  ' <<< "${input}"
}

smudgeSettings() {
  if [[ ! -f "${STASH_FILE}" ]]; then
    exec cat
  fi

  jq --indent 2 --slurpfile stash "${STASH_FILE}" '
    $stash[0] as $private
    | reduce ($private.hooks // {} | to_entries[]) as $event (.;
        .hooks[$event.key] = ((.hooks[$event.key] // []) as $groups | $groups + [ $event.value[] | select(. as $group | $groups | index([$group]) | not) ]))
    | reduce ($private.permissions // {} | to_entries[]) as $kind (.;
        .permissions[$kind.key] = ((.permissions[$kind.key] // []) as $rules | $rules + [ $kind.value[] | select(. as $rule | $rules | index([$rule]) | not) ]))
  '
}

case "${MODE}" in
  clean) cleanSettings ;;
  smudge) smudgeSettings ;;
  *) echo "알 수 없는 모드: ${MODE}" >&2; exit 2 ;;
esac
