#!/bin/bash
#
# SwiftBar 플러그인 — dotfiles 자동 갱신 (scripts/dotfiles-auto-update.sh) 이 손을 필요로 할 때만 메뉴 막대에 뜬다.
# 파일명 규칙이 곧 설정이다: <이름>.<갱신주기>.<확장자> — 5m = 5 분마다 재실행 (자동 갱신이 끝나면 바로 다시 그려 달라고도 한다).
#
# 상태 파일만 읽는다 (네트워크 · git 호출 없음). 손 필요한 것이 없으면 아무것도 출력하지 않는다 —
# SwiftBar 는 빈 출력이면 메뉴 막대에 항목을 두지 않는다.
#
# 띄우는 것: 손 필요 · 실패, 하루 넘게 이어진 "받아오지 못함", 3일 넘게 돌지 않은 자동 갱신.
# 줄마다 상태 파일의 메뉴 줄 ("<대상>: <짧은 상태>") 만 쓴다 — 상세 (이름 · 이유 · 할 일) 는 로그와 메일에 있다.
# 어떤 문구가 와도 메뉴가 화면 폭을 넘지 않게 MAX_CHARS 글자에서 자른다.
#
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

export PATH=/usr/bin:/bin:/usr/sbin
export LC_ALL=en_US.UTF-8   # 한글을 바이트가 아니라 글자 단위로 자르게

STATUS="${HOME}/.local/state/dotfiles-update/status"
LOG="${HOME}/Library/Logs/dotfiles-auto-update.log"
UPDATER="${HOME}/.local/bin/dotfiles-auto-update"
UNREACHABLE_GRACE_SECONDS=$((24 * 3600))
STALE_SECONDS=$((3 * 24 * 3600))
MAX_CHARS=40

[[ -f "${STATUS}" ]] || exit 0

NOW=$(date +%s)

# 띄울 줄: <대상>\t<메뉴 줄>. 메뉴 줄 칸 ($5) 이 없는 줄 (옛 판이 적은 줄) 은 "<대상>: <상세>" 로 쓴다
ITEMS=$(awk -F'\t' -v now="${NOW}" -v grace="${UNREACHABLE_GRACE_SECONDS}" -v stale="${STALE_SECONDS}" '
    $1 == "last_run" { if (now - $3 > stale) printf "자동 갱신\t자동 갱신: %d일째 돌지 않음\n", (now - $3) / 86400; next }
    { line = (length($5) > 0 ? $5 : $1 ": " $3) }
    $2 == "manual" || $2 == "failed" { printf "%s\t%s\n", $1, line; next }
    $2 == "unreachable" && now - $4 > grace { printf "%s\t%s (하루 넘게)\n", $1, line; next }
' "${STATUS}")

[[ -n "${ITEMS}" ]] || exit 0

COUNT=$(grep -c . <<<"${ITEMS}")
LAST_RUN=$(awk -F'\t' '$1 == "last_run" { print $2 }' "${STATUS}")

echo "↓${COUNT} | sfimage=arrow.triangle.2.circlepath sfcolor=orange"
echo "---"

while IFS=$'\t' read -r target line; do
    (( ${#line} <= MAX_CHARS )) || line="${line:0:$((MAX_CHARS - 1))}…"
    line=${line//|/·}   # SwiftBar 는 | 뒤를 설정으로 읽는다
    echo "${line} | color=orange"

    # Brewfile 표시는 사람이 make update 를 했거나 넘기기로 했을 때 지운다 (다음 자동 갱신도 깔렸는지 다시 본다)
    if [[ "${target}" == "brewfile" ]]; then
        echo "--확인함 (표시 지우기) | bash=${UPDATER} param1=--dismiss param2=brewfile terminal=false refresh=true"
    fi
done <<<"${ITEMS}"

echo "---"
echo "마지막 실행: ${LAST_RUN:-기록 없음} | color=gray"
echo "지금 업데이트 (안전한 것만 받음) | bash=${UPDATER} terminal=false refresh=true"
echo "로그 열기 | bash=/usr/bin/open param1=-t param2=${LOG} terminal=false"
