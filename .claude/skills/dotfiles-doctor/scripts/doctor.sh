#!/usr/bin/env bash
# dotfiles 의 기계적 점검 — 읽기 전용. 아무것도 고치지 않는다.
# 출력: [FAIL] 확실한 고장 / [WARN] 사람이 판단할 것 / [INFO] 판단 재료. FAIL 이 하나라도 있으면 exit 1.
#
# set -e 를 쓰지 않는 이유: 점검 하나가 실패해도 나머지 점검을 끝까지 돌려야 한다.
set -uo pipefail

DOTFILES="${DOTFILES:-${HOME}/.dotfiles}"
fail_count=0

fail() { printf '[FAIL] %s\n' "$*"; fail_count=$(( fail_count + 1 )); }
warn() { printf '[WARN] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

# Makefile 변수 값 출력 (make 3.81 은 --eval 이 없어서 stdin makefile 로 include 한다)
print_make_var() {
  printf 'include Makefile\nprint-%%:\n\t@echo $($*)\n' | make -s -C "${DOTFILES}" -f - "print-${1}" 2>/dev/null
}

cd "${DOTFILES}" || { echo "[FAIL] ${DOTFILES} 없음"; exit 1; }

# --- 1. Makefile 링크 매핑: 원본 존재 + $HOME 쪽이 그 원본을 가리키는 링크인가 ---
echo "## 1. Makefile 링크 매핑"

for entry in $(print_make_var LINKS_SINGLE) $(print_make_var LINKS_DIR); do
  src="${DOTFILES}/${entry%%:*}"
  dst="${HOME}/${entry##*:}"

  [[ -e "${src}" ]] || { fail "원본 없음: ${entry%%:*} (Makefile 매핑만 남음)"; continue; }

  if [[ ! -L "${dst}" ]]; then
    warn "링크 아님: ~/${entry##*:} (make sync 미실행이거나 실파일이 막고 있음)"
  elif [[ "$(readlink "${dst}")" != "${src}" ]]; then
    warn "다른 곳을 가리킴: ~/${entry##*:} -> $(readlink "${dst}")"
  fi
done

# --- 2. 와일드카드 링크 디렉토리의 끊긴 링크 (원본이 삭제된 명령·스킬·에이전트) ---
echo "## 2. 끊긴 심볼릭 링크"

for dir in "${HOME}/.claude/commands" "${HOME}/.claude/skills" "${HOME}/.claude/agents"; do
  [[ -d "${dir}" ]] || continue

  while IFS= read -r link; do
    target=$(readlink "${link}")
    [[ "${target}" == "${DOTFILES}"/* ]] || continue
    [[ -e "${link}" ]] || fail "끊긴 링크: ${link/#${HOME}/~} -> ${target/#${HOME}/~}"
  done < <(find "${dir}" -maxdepth 1 -type l)
done

# --- 3. 문법 ---
echo "## 3. 문법"

while IFS= read -r f; do
  bash -n "${f}" 2>/dev/null || fail "bash 문법 오류: ${f}"
done < <(git ls-files '*.sh')

while IFS= read -r f; do
  jq empty "${f}" 2>/dev/null || fail "JSON 문법 오류: ${f}"
done < <(git ls-files '*.json')

make -n sync >/dev/null 2>&1 || fail "make -n sync 실패"

# --- 4. settings.json 훅·상태줄이 부르는 스크립트가 있는가 ---
echo "## 4. Claude 훅 스크립트"

while IFS= read -r script; do
  [[ -f "${DOTFILES}/claude/scripts/${script}" ]] || fail "settings.json 이 없는 스크립트를 부름: ~/.claude/scripts/${script}"
done < <(jq -r '.. | .command? // empty' claude/settings.json | grep -oE '~/\.claude/scripts/[A-Za-z0-9._-]+' | sed 's|.*/||' | sort -u)

# --- 5. 문서가 가리키는 경로가 있는가 ---
# 백틱 안의 '/' 가 들어간 경로만 본다. 자리표시자 (<, *, {, $) 와 다른 프로젝트 기준 경로 (.claude/, .prompts/, harness/) 는 제외.
# ~/ 경로는 dotfiles 가 링크하는 ~/.claude/ 하위만 본다 (그 밖은 머신별 선택 파일이라 없어도 정상).
# 상대 경로는 저장소 루트 · claude/ · 문서 자신의 디렉토리 중 하나에 있으면 통과.
echo "## 5. 문서 속 경로"

while IFS= read -r doc; do
  doc_dir=$(dirname "${doc}")

  while IFS= read -r ref; do
    path="${ref#@}"
    path="${path%%#*}"

    [[ "${path}" =~ [\<\*\{\$] ]] && continue
    [[ "${path}" =~ ^(\.claude|\.prompts|harness)/ ]] && continue

    [[ "${path}" == */* ]] || continue

    if [[ "${path}" == "~/"* ]]; then
      [[ "${path}" =~ ^~/\.claude/(docs|rules|scripts|agents|commands|skills)/ ]] || continue
      [[ -e "${HOME}/${path#\~/}" ]] || warn "${doc}: \`${ref}\` 없음"
      continue
    fi

    [[ -e "${path}" || -e "claude/${path}" || -e "${doc_dir}/${path}" ]] || warn "${doc}: \`${ref}\` 없음"
  done < <(grep -oE '`@?~?/?[A-Za-z0-9._/-]+\.(md|sh|json|toml|plist)`' "${doc}" | tr -d '`' | sort -u)
done < <(git ls-files 'AGENTS.md' 'docs/*.md' 'claude/*.md' 'claude/**/*.md' '.claude/skills/**/*.md')

# --- 6. 판단 재료: 현재 Claude Code 버전과 문서가 기준으로 삼은 버전 ---
echo "## 6. 버전 기준"

info "현재 Claude Code: $(claude --version 2>/dev/null | head -1)"

grep -rnoE '[0-9]+\.[0-9]+\.[0-9]+\** (기준|에서)' claude .claude/skills 2>/dev/null \
  | while IFS= read -r hit; do info "문서 기준 버전: ${hit}"; done

echo
echo "FAIL ${fail_count}건"
(( fail_count == 0 ))
