#!/bin/bash
#
# SwiftBar 플러그인 — dotfiles 자동 갱신 (scripts/dotfiles-auto-update.sh) 이 손을 필요로 할 때만 메뉴 막대에 뜬다.
# 파일명 규칙이 곧 설정이다: <이름>.<갱신주기>.<확장자> — 5m = 5 분마다 재실행 (자동 갱신이 끝나면 바로 다시 그려 달라고도 한다).
#
# 상태 파일만 읽는다 (네트워크 · git 호출 없음). 직접 확인 필요한 것이 없으면 아무것도 출력하지 않는다 —
# SwiftBar 는 빈 출력이면 메뉴 막대에 항목을 두지 않는다.
#
# 띄우는 것: 직접 확인 필요 · 실패, 하루 넘게 이어진 "받아오지 못함", 3일 넘게 돌지 않은 자동 갱신.
# 줄마다 상태 파일의 메뉴 줄 ("<대상>: <짧은 상태>") 을 쓰고, 그 줄의 하위 메뉴에 상세 · 시작 시각 · 이번 실행의 오류 문장을 둔다
# (줄 자체는 누르는 단추가 아니다 — 다시 시도는 "지금 업데이트"). 자동 갱신이 도는 동안에는 제목과 마지막 줄이 "갱신 중" 이 된다.
# 어떤 문구가 와도 메뉴가 화면 폭을 넘지 않게 MAX_CHARS (하위 메뉴는 SUB_MAX_CHARS) 글자에서 자른다.
#
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

export PATH=/usr/bin:/bin:/usr/sbin
export LC_ALL=en_US.UTF-8   # 한글을 바이트가 아니라 글자 단위로 자르게

STATUS="${HOME}/.local/state/dotfiles-update/status"
LOCK="${HOME}/.local/state/dotfiles-update/lock"
LOG="${HOME}/Library/Logs/dotfiles-auto-update.log"
UPDATER="${HOME}/.local/bin/dotfiles-auto-update"
UNREACHABLE_GRACE_SECONDS=$((24 * 3600))
STALE_SECONDS=$((3 * 24 * 3600))
MAX_CHARS=40
SUB_MAX_CHARS=60

[[ -f "${STATUS}" ]] || exit 0

NOW=$(date +%s)

# 인자: 글자 수, 문구 — 글자 수에서 자르고 SwiftBar 가 설정으로 읽는 | 를 바꿔 출력한다
fitLine() {
    local limit=$1
    local text=$2

    (( ${#text} <= limit )) || text="${text:0:$((limit - 1))}…"

    echo "${text//|/·}"
}

# 인자: 대상 — 마지막 실행에서 그 대상이 남긴 오류 문장 (상태 줄 "<대상>: <상태> —" 은 빼고, git 의 긴 머리말은 줄인다)
lastError() {
    awk -v prefix="$1: " '
        / ===== 시작 =====$/ { found = ""; next }
        {
            text = substr($0, 21)
            if (index(text, prefix) != 1) next
            text = substr(text, length(prefix) + 1)
            if (text ~ /^(latest|updated|manual|failed|skipped|unreachable) — /) next
            found = text
        }
        END { print found }
    ' "${LOG}" 2>/dev/null | sed -E "s/fatal: //; s/unable to access '[^']*': //"
}

# 띄울 줄: <대상>\t<메뉴 줄>\t<상세>\t<시작 epoch>. 메뉴 줄 칸 ($5) 이 없는 줄 (옛 판이 적은 줄) 은 "<대상>: <상세>" 로 쓴다
ITEMS=$(awk -F'\t' -v now="${NOW}" -v grace="${UNREACHABLE_GRACE_SECONDS}" -v stale="${STALE_SECONDS}" '
    $1 == "last_run" { if (now - $3 > stale) printf "자동 갱신\t자동 갱신: %d일째 돌지 않음\t\t\n", (now - $3) / 86400; next }
    { line = (length($5) > 0 ? $5 : $1 ": " $3) }
    $2 == "manual" || $2 == "failed" { printf "%s\t%s\t%s\t%s\n", $1, line, $3, $4; next }
    $2 == "unreachable" && now - $4 > grace { printf "%s\t%s (하루 넘게)\t%s\t%s\n", $1, line, $3, $4; next }
' "${STATUS}")

[[ -n "${ITEMS}" ]] || exit 0

COUNT=$(grep -c . <<<"${ITEMS}")
LAST_RUN=$(awk -F'\t' '$1 == "last_run" { print $2 }' "${STATUS}")

# 자동 갱신이 도는 중인지 — 잠금의 pid 가 살아 있으면 그 잠금을 만든 시각을 시작 시각으로 쓴다
RUNNING_SINCE=""
holder=$(cat "${LOCK}/pid" 2>/dev/null || true)

if [[ -n "${holder}" ]] && kill -0 "${holder}" 2>/dev/null; then
    RUNNING_SINCE=$(stat -f '%Sm' -t '%H:%M' "${LOCK}")
fi

if [[ -n "${RUNNING_SINCE}" ]]; then
    echo "갱신 중… | sfimage=arrow.triangle.2.circlepath sfcolor=gray"
else
    echo "↓${COUNT} | sfimage=arrow.triangle.2.circlepath sfcolor=orange"
fi

echo "---"

while IFS=$'\t' read -r target line detail since; do
    echo "$(fitLine "${MAX_CHARS}" "${line}") | color=orange"

    # 상세는 " — " 앞뒤 (무엇 · 할 일) 를 줄로 나눠 보인다
    if [[ -n "${detail}" ]]; then
        while IFS= read -r part; do
            echo "--$(fitLine "${SUB_MAX_CHARS}" "${part}")"
        done <<<"${detail// — /$'\n'}"
    fi

    if [[ -n "${since}" ]]; then
        echo "--시작: $(date -r "${since}" '+%m-%d %H:%M') | color=gray"
    fi

    error=$(lastError "${target}")

    if [[ -n "${error}" ]]; then
        echo "--오류: $(fitLine "${SUB_MAX_CHARS}" "${error}") | color=gray"
    fi

    # Brewfile 표시는 사람이 make update 를 했거나 넘기기로 했을 때 지운다 (다음 자동 갱신도 깔렸는지 다시 본다)
    if [[ "${target}" == "brewfile" ]]; then
        echo "-----"
        echo "--확인함 (표시 지우기) | bash=${UPDATER} param1=--dismiss param2=brewfile terminal=false refresh=true"
    fi
done <<<"${ITEMS}"

echo "---"
echo "마지막 실행: ${LAST_RUN:-기록 없음} | color=gray"

if [[ -n "${RUNNING_SINCE}" ]]; then
    echo "갱신 중… (${RUNNING_SINCE} 시작 — 끝나면 이 메뉴가 바뀜) | color=gray"
else
    echo "지금 업데이트 (안전한 것만 받음) | bash=${UPDATER} terminal=false refresh=true"
fi

echo "로그 열기 | bash=/usr/bin/open param1=-t param2=${LOG} terminal=false"
