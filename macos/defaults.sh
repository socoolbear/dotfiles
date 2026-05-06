#!/usr/bin/env bash
# macOS 시스템 기본값 (defaults write) — 핵심 4 개
# 사용법: make macos
#
# 정책: 사용자 취향이 갈리지 않는 안전한 항목만. Dock / Finder 표시 옵션 등은 제외.

set -euo pipefail

step() { printf '==> %s\n' "$1"; }

#--------------------------------------------------------------------------
# 키보드
#--------------------------------------------------------------------------

step "키 길게 누름 시 액센트 팝업 비활성화 (vim 사용 필수)"
defaults write -g ApplePressAndHoldEnabled -bool false

step "키 반복 속도 (최저값)"
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

#--------------------------------------------------------------------------
# Finder
#--------------------------------------------------------------------------

step "모든 파일 확장자 표시"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

#--------------------------------------------------------------------------
# 스크린샷
#--------------------------------------------------------------------------

step "스크린샷 저장 위치 (~/Pictures/Screenshots)"
mkdir -p "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"

#--------------------------------------------------------------------------
# 적용
#--------------------------------------------------------------------------

killall Finder >/dev/null 2>&1 || true

echo
echo "macOS defaults 적용 완료."
echo "  - ApplePressAndHoldEnabled 변경은 앱 재실행 후 적용됩니다."
echo "  - 일부 항목은 재로그인 후 완전히 반영됩니다."
