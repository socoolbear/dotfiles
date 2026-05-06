#!/usr/bin/env bash
# bootstrap.sh — 새 macOS 장비 1-shot 셋업
# 사용법:
#   curl -fsSL https://raw.githubusercontent.com/socoolbear/dotfiles/master/bootstrap.sh | bash
#   또는 git clone 후: bash bootstrap.sh

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/socoolbear/dotfiles.git}"

step() { printf '\n==> %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }

#--------------------------------------------------------------------------
# 1. Xcode Command Line Tools
#--------------------------------------------------------------------------

if ! xcode-select -p >/dev/null 2>&1; then
    step "Xcode Command Line Tools 설치"
    xcode-select --install || true
    echo "설치 창이 뜨면 완료 후 본 스크립트를 다시 실행하세요."
    exit 1
fi

#--------------------------------------------------------------------------
# 2. Homebrew
#--------------------------------------------------------------------------

if ! command -v brew >/dev/null 2>&1; then
    step "Homebrew 설치"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

#--------------------------------------------------------------------------
# 3. dotfiles clone (이미 있으면 스킵)
#--------------------------------------------------------------------------

if [ ! -d "$DOTFILES" ]; then
    step "dotfiles clone → $DOTFILES"
    git clone "$DOTFILES_REPO" "$DOTFILES"
fi

cd "$DOTFILES"

#--------------------------------------------------------------------------
# 4. 작업 디렉토리
#--------------------------------------------------------------------------

mkdir -p "$HOME/code" "$HOME/.local/bin"

#--------------------------------------------------------------------------
# 5. Make 타겟들
#--------------------------------------------------------------------------

step "Brewfile 적용 (코어)"
make brew

step "심볼릭 링크 생성"
make sync

step "NPM globals 설치"
make npm || warn "node/npm 미설치. 'nvm install --lts' 후 'make npm' 재실행."

step "macOS defaults 적용"
make macos

#--------------------------------------------------------------------------
# 6. 후속 안내
#--------------------------------------------------------------------------

cat <<'EOF'

==> 셋업 완료. 추가로 처리할 항목:
  - make brew-apps      # GUI 앱 (Brewfile.apps) 의 주석 해제 후 설치
  - mas 항목 사용 시 App Store 로그인 후 make brew-apps 재실행
  - ~/.gitconfig_local 에 호스트별 user.email / includeIf 작성
  - ~/.private-exports 에 토큰 입력 (zsh/private.export.example 참고)
  - 1Password / JetBrains / Alfred 등 라이센스 / 계정 입력

새 셸 시작: exec zsh
EOF
