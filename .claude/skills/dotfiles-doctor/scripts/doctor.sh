#!/usr/bin/env bash
# dotfiles 의 기계적 점검 — 읽기 전용. 아무것도 고치지 않는다.
# 출력: [FAIL] 확실한 고장 / [WARN] 사람이 판단할 것 / [INFO] 판단 재료. FAIL 이 하나라도 있으면 exit 1.
#
# set -e 를 쓰지 않는 이유: 점검 하나가 실패해도 나머지 점검을 끝까지 돌려야 한다.
set -uo pipefail

DOTFILES="${DOTFILES:-${HOME}/.dotfiles}"
GITLEAKS_CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/gitleaks.toml"   # cd 전에 이 스크립트 위치 기준으로 잡는다
fail_count=0
tilde="~"   # 경로 표시용. ${x/#${HOME}/~} 처럼 ~ 를 바로 쓰면 bash 5.x 는 홈 경로로 다시 풀어 버린다

fail() { printf '[FAIL] %s\n' "$*"; fail_count=$(( fail_count + 1 )); }
warn() { printf '[WARN] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

# Makefile 변수 값 출력 (make 3.81 은 --eval 이 없어서 stdin makefile 로 include 한다)
print_make_var() {
  printf 'include Makefile\nprint-%%:\n\t@echo $($*)\n' | make -s -C "${DOTFILES}" -f - "print-${1}" 2>/dev/null
}

cd "${DOTFILES}" || { echo "[FAIL] ${DOTFILES} 없음"; exit 1; }

# 한글 등 비 ASCII 경로를 \355... 로 감싸지 않게 한다
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotepath GIT_CONFIG_VALUE_0=false

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

# 링크가 놓이는 디렉토리 (Makefile 매핑 대상의 상위 + 와일드카드 + Alfred) 를 훑어,
# dotfiles 를 가리키는데 원본이 없는 링크를 찾는다 (매핑에서 빠진 낡은 링크 포함)
link_parents=$(
  for entry in $(print_make_var LINKS_SINGLE) $(print_make_var LINKS_DIR); do dirname "${HOME}/${entry##*:}"; done
  printf '%s\n' "${HOME}/.claude/commands" "${HOME}/.claude/skills" "${HOME}/.claude/agents" "$(print_make_var ALFRED_WORKFLOWS_DIR)"
)

while IFS= read -r dir; do
  [[ -d "${dir}" ]] || continue

  while IFS= read -r link; do
    target=$(readlink "${link}")
    [[ "${target}" == "${DOTFILES}"/* ]] || continue
    [[ -e "${link}" ]] || fail "끊긴 링크: ${link/#${HOME}/${tilde}} -> ${target/#${HOME}/${tilde}}"
  done < <(find "${dir}" -maxdepth 1 -type l)
done < <(printf '%s\n' "${link_parents}" | grep -v '^$' | sort -u)

# --- 3. 문법 ---
echo "## 3. 문법"

while IFS= read -r f; do
  bash -n "${f}" 2>/dev/null || fail "bash 문법 오류: ${f}"
done < <(git ls-files '*.sh')

while IFS= read -r f; do
  jq empty "${f}" 2>/dev/null || fail "JSON 문법 오류: ${f}"
done < <(git ls-files '*.json')

# 셸·git·plist 설정은 읽히는지만 본다 (깨진 설정이 push 되면 다른 장비의 새 터미널이 오류로 열린다)
zsh -n zsh/zshrc 2>/dev/null || fail "zsh 문법 오류: zsh/zshrc"
git config -f git/gitconfig --list >/dev/null 2>&1 || fail "git 설정 파싱 오류: git/gitconfig"

while IFS= read -r f; do
  plutil -lint "${f}" >/dev/null 2>&1 || fail "plist 문법 오류: ${f}"
done < <(git ls-files '*.plist')

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

# --- 5-1. 스킬·에이전트·명령 정의의 frontmatter (name · description) ---
echo "## 5-1. 정의 파일 frontmatter"

while IFS= read -r def; do
  head -1 "${def}" | grep -qx -- '---' || { fail "frontmatter 없음: ${def}"; continue; }
  [[ $(grep -cx -- '---' "${def}") -ge 2 ]] || { fail "frontmatter 를 닫는 --- 없음: ${def}"; continue; }
  front=$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "${def}")
  grep -qE '^description:[[:space:]]*[^[:space:]]' <<< "${front}" || fail "description 없음 또는 빈 값: ${def}"
  [[ "${def}" == */commands/* ]] || grep -q '^name:' <<< "${front}" || fail "name 없음: ${def}"
done < <(git ls-files --cached --others --exclude-standard '.claude/skills/*/SKILL.md' 'claude/skills/*/SKILL.md' 'claude/agents/*.md' 'claude/commands/*.md')

# --- 6. 판단 재료: 현재 Claude Code 버전과 문서가 기준으로 삼은 버전 ---
echo "## 6. 버전 기준"

info "현재 Claude Code: $(claude --version 2>/dev/null | head -1)"

grep -rnoE '[0-9]+\.[0-9]+\.[0-9]+\** (기준|에서)' claude .claude/skills 2>/dev/null \
  | while IFS= read -r hit; do info "문서 기준 버전: ${hit}"; done

# --- 7. 저장소 구성: docs/structure.md 「디렉토리 개요」 표가 역할 목록이다 ---
# 새 디렉토리가 생겨도 이 스크립트는 고칠 필요가 없다. 표에 없는 디렉토리를 WARN 으로 올린다.
echo "## 7. 저장소 구성"

structure="docs/structure.md"
listed=$(awk '/^## 디렉토리 개요/{on=1; next} /^## /{on=0} on' "${structure}" \
  | grep -oE '^\| `[^`]+/`' | sed -E 's/^\| `//; s/\/`$//' | sort -u)

if [[ -z "${listed}" ]]; then
  fail "${structure} 의 '## 디렉토리 개요' 표를 읽지 못함 (제목·형식이 바뀌었으면 이 절을 고칠 것)"
  listed="(파싱 실패)"
fi

while IFS= read -r dir; do
  grep -qxF "${dir}" <<< "${listed}" \
    || warn "${structure} 에 역할이 없는 디렉토리: ${dir}/ — 표에 역할을 추가하고 공통 점검 기준으로 볼 것"
done < <(git ls-files --cached --others --exclude-standard | grep / | cut -d/ -f1 | sort -u)   # 커밋 전 새 디렉토리도 잡는다

while IFS= read -r dir; do
  [[ "${dir}" == "(파싱 실패)" || -d "${dir}" ]] || fail "${structure} 표에 있지만 없는 디렉토리: ${dir}/"
done <<< "${listed}"

# 최상위 파일은 역할 표가 따로 없으므로, 저장소 안내 문서 어디에도 이름이 없을 때만 올린다
while IFS= read -r file; do
  file_re=$(printf '%s' "${file}" | sed 's/[.[\*^$]/\\&/g')
  grep -qE "(^|[^A-Za-z0-9_.-])${file_re}([^A-Za-z0-9_-]|$)" AGENTS.md README.md "${structure}" docs/*.md 2>/dev/null \
    || warn "어느 안내 문서에도 없는 최상위 파일: ${file}"
done < <(git ls-files --cached --others --exclude-standard | grep -v / | grep -vxE '\.gitignore|LICENSE|CLAUDE\.md|AGENTS\.md|README\.md')

# 자동 링크 ✅ 인데 Makefile 이 그 디렉토리를 전혀 언급하지 않으면 링크가 빠진 것
while IFS= read -r dir; do
  grep -qE "(^|[[:space:]/(])${dir}[/:]" Makefile || warn "${structure} 은 자동 링크 ✅ 인데 Makefile 에 ${dir}/ 언급 없음"
done < <(awk '/^## 디렉토리 개요/{on=1; next} /^## /{on=0} on' "${structure}" \
  | grep -E '✅' | grep -oE '^\| `[^`]+/`' | sed -E 's/^\| `//; s/\/`$//')

# 마지막 doctor 실행 커밋 (제목이 'doctor:' 로 시작 — 본문은 보지 않는다) 이후 바뀐 최상위 항목 — 우선 점검 대상
# 커밋된 변경 + 작업 트리의 미커밋·미추적 변경을 합친다.
last_run=$(git log --format='%h%x09%s' | awk -F'\t' 'index($2, "doctor:") == 1 { print $1; exit }')
worktree_changed=$(git status --porcelain --no-renames | cut -c4- | cut -d/ -f1)

if [[ -n "${last_run}" ]]; then
  changed=$( { git diff --name-only "${last_run}..HEAD" | cut -d/ -f1; printf '%s\n' "${worktree_changed}"; } | grep -v '^$' | sort -u | tr '\n' ' ')
  info "마지막 doctor 실행: ${last_run} — 이후 바뀐 최상위 항목: ${changed:-(없음)}"
else
  info "이전 doctor 실행 커밋 없음 — 전체를 같은 깊이로 점검"
fi

# --- 8. 민감 정보: 공개 저장소에 비밀키·개인정보·회사/사람 이름이 들어갔는가 ---
# 작업 트리 (미커밋·미추적 포함) 와 git 이력 (커밋 메시지·작성자 포함) 을 본다.
# 회사·사람 이름은 저장소에 적으면 그 자체로 노출이므로 목록을 저장소 밖에 둔다 (한 줄에 정규식 하나, # 주석).
# 이력에만 남은 것도 FAIL 이다 — 지우려면 이력 재작성 + force push 가 필요하므로 doctor 는 고치지 않고 묻는다.
# 이미 무효화한 비밀키는 `gitleaks git` 출력의 Fingerprint 를 .gitleaksignore 에 넣어 끈다.
# gitleaks 기본 규칙이 모르는 형식 (ntfy 토픽 · Discord 웹훅 등) 은 같은 폴더의 gitleaks.toml 에 규칙을 더한다.
# --exit-code 3 은 비밀키 발견, 그 밖의 0 아닌 값은 gitleaks 자체 오류 (설정 파일 등) — 섞으면 설정이 깨졌을 때 매 세션 거짓 경보가 난다.
echo "## 8. 민감 정보"

sensitive_words="${XDG_CONFIG_HOME:-${HOME}/.config}/dotfiles/sensitive-words"

print_worktree() {
  git diff HEAD
  git ls-files --others --exclude-standard -z | xargs -0 cat 2>/dev/null
}

if command -v gitleaks >/dev/null 2>&1; then
  config_display="${GITLEAKS_CONFIG_FILE/#${HOME}/${tilde}}"

  # 인자: 대상 이름, 확인 명령, 종료 코드 (파이프라인이면 gitleaks 쪽 PIPESTATUS 를 넘긴다)
  report_gitleaks() {
    case "${3}" in
      0) ;;
      3) fail "gitleaks: ${1}에 비밀키 의심 — '${2}' 로 확인" ;;
      *) fail "gitleaks: 실행 실패 (exit ${3} — 설정 파일 ${config_display} 등 확인)" ;;
    esac
  }

  gitleaks git -c "${GITLEAKS_CONFIG_FILE}" --redact --no-banner --log-level error --exit-code 3 . >/dev/null 2>&1
  report_gitleaks "git 이력" "gitleaks git -c ${config_display} --redact -v" "$?"

  print_worktree | gitleaks stdin -c "${GITLEAKS_CONFIG_FILE}" --redact --no-banner --log-level error --exit-code 3 >/dev/null 2>&1
  report_gitleaks "미커밋·미추적 변경" "git diff HEAD | gitleaks stdin -c ${config_display} --redact -v (미추적 파일도)" "${PIPESTATUS[1]}"
else
  warn "gitleaks 없음 — 비밀키 점검 건너뜀 (make brew)"
fi

if [[ -s "${sensitive_words}" ]]; then
  words=$(grep -vE '^[[:space:]]*(#|$)' "${sensitive_words}")

  while IFS= read -r hit; do
    fail "금지어 (작업 트리): ${hit:0:160}"
  done < <(git grep -I -n -i -E --untracked -f <(printf '%s\n' "${words}") 2>/dev/null)

  history_hits=$(git log --all -p --format='commit %h%nAuthor: %an <%ae>%n%B' | grep -i -c -E -f <(printf '%s\n' "${words}"))
  (( history_hits == 0 )) || fail "금지어 (git 이력): ${history_hits}줄 — git log --all -p --format=fuller | grep -i -n -E -f ${sensitive_words/#${HOME}/${tilde}}"
else
  info "금지어 목록 없음 (${sensitive_words/#${HOME}/${tilde}}) — 회사·사람 이름 점검 건너뜀"
fi

# 형식으로 잡히는 개인정보 (휴대폰 번호 · 주민등록번호) — 예시 값일 수 있어 WARN
while IFS= read -r hit; do
  warn "개인정보 형식: ${hit:0:160}"
done < <(git grep -I -n -E --untracked '01[016789]-?[0-9]{3,4}-?[0-9]{4}|[0-9]{6}-[1-4][0-9]{6}' 2>/dev/null)

echo
echo "FAIL ${fail_count}건"
(( fail_count == 0 ))
