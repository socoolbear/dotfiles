#!/usr/bin/env bash
# brew-cleanup.sh — Brewfile 에 등록되지 않은 brew/cask/mas/tap 패키지를 정리한다.
#
# 사용법:
#   ./scripts/brew-cleanup.sh           # dry-run (제거 후보만 출력)
#   ./scripts/brew-cleanup.sh --force   # 실제 제거
#   ./scripts/brew-cleanup.sh --zap     # cask 는 uninstall 대신 zap (앱 데이터까지 삭제)
#
# 동작:
#   Brewfile, Brewfile.apps, Brewfile.work (있으면), Brewfile.local (있으면)
#   네 파일을 합쳐서 brew bundle cleanup 의 입력으로 전달.
#   하나라도 빠뜨리면 해당 파일에만 있던 패키지가 제거 대상이 되므로 주의.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew 가 설치되어 있지 않습니다." >&2
    exit 1
fi

# 옵션 파싱
FORCE=""
ZAP=""
for arg in "$@"; do
    case "${arg}" in
        -f|--force) FORCE="--force" ;;
        --zap)      ZAP="--zap"; FORCE="--force" ;;
        -h|--help)
            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "ERROR: 알 수 없는 옵션: ${arg}" >&2
            echo "사용법: $0 [--force] [--zap]" >&2
            exit 2
            ;;
    esac
done

# 모든 Brewfile 을 임시 파일로 합치기
TMP="$(mktemp -t brewfile-merged.XXXXXX)"
trap 'rm -f "${TMP}"' EXIT

MERGED_FILES=()
for name in Brewfile Brewfile.apps Brewfile.work Brewfile.local; do
    path="${DOTFILES}/${name}"
    if [[ -f "${path}" ]]; then
        printf '\n# === %s ===\n' "${name}" >> "${TMP}"
        cat "${path}" >> "${TMP}"
        MERGED_FILES+=("${name}")
    fi
done

if [[ ${#MERGED_FILES[@]} -eq 0 ]]; then
    echo "ERROR: ${DOTFILES} 에 Brewfile 이 없습니다." >&2
    exit 1
fi

echo "==> 합친 Brewfile: ${MERGED_FILES[*]}"

if [[ -z "${FORCE}" ]]; then
    echo "==> dry-run (실제 제거하려면 --force 또는 --zap)"
    # cleanup 은 제거 대상이 있으면 exit 1 — 정상이므로 || true
    brew bundle cleanup --file="${TMP}" || true
else
    echo "==> 실제 제거 진행 (${FORCE} ${ZAP})"
    brew bundle cleanup --file="${TMP}" ${FORCE} ${ZAP}
fi
