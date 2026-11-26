#!/usr/bin/env bash
# git clean 필터 — claude/settings.json 을 커밋할 때 비공개 항목을 빼고 넘긴다.
# 작업 파일 (~/.claude/settings.json 이 가리키는 파일) 은 그대로 두고, 저장소에 들어가는 내용에서만 뺀다.
# 외부 도구 (setup 명령 등) 가 settings.json 에 직접 넣는 회사 전용 훅·권한 규칙을 공개 저장소에 올리지 않으려는 것.
#
# 뺄 낱말 목록: ~/.config/claude/settings-private-patterns (한 줄에 하나, # 은 주석). 비공개 파일이라 이 저장소에 두지 않는다.
# 낱말이 든 hooks 묶음 (그 묶음의 command 중 하나라도) 과 permissions.allow·ask·deny 항목을 뺀다.
# 목록 파일이 없으면 그대로 넘긴다. 연결: Makefile sync 가 filter.claude-private 를 설정하고 .gitattributes 가 이 파일에 건다.
set -euo pipefail

PATTERNS_FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/settings-private-patterns"

if [[ ! -f "${PATTERNS_FILE}" ]]; then
  exec cat
fi

patterns=$(grep -v '^[[:space:]]*\(#\|$\)' "${PATTERNS_FILE}" | jq -R . | jq -sc .)

jq --indent 2 --argjson patterns "${patterns}" '
  def private: . as $text | any($patterns[]; . as $pattern | $text | contains($pattern));
  def drop_private_hooks:
    [ .[] | select(any(.hooks[]?; (.command // "") | private) | not) ];
  def drop_private_rules:
    [ .[] | select(private | not) ];

  (if (.hooks | type) == "object" then
    .hooks |= with_entries(
      .value as $groups
      | .value |= drop_private_hooks
      | select((.value | length) > 0 or ($groups | length) == 0)
    )
  else . end)
  | (if (.permissions | type) == "object" then
    .permissions |= with_entries(
      if (.key | IN("allow", "ask", "deny")) and (.value | type) == "array" then
        .value as $rules
        | .value |= drop_private_rules
        | select((.value | length) > 0 or ($rules | length) == 0)
      else . end
    )
  else . end)
'
