# Dotfiles

macOS 개발 환경을 위한 개인 dotfiles. Makefile 기반 심볼릭 링크로 관리합니다.

## 사전 준비

### 필수 도구 (Homebrew)

```shell
brew install \
  curl wget zsh tmux git make gcc bat \
  nvm \
  awscli
```

> `node` / `npm` 은 `nvm install <version>` 으로 설치 (Homebrew node 와 충돌 방지)

### 폰트

```shell
brew install --cask font-jetbrains-mono-nerd-font
```

다른 Nerd Font 가 필요하면 [getnf](https://github.com/ronniedroid/getnf) 사용.

### 패키지 매니저 / CLI

```shell
npm install -g pnpm@latest-10
npm install -g @nestjs/cli
```

### SSH

- **권장**: 1Password SSH agent 활성화
- **대안**: `ssh-keygen -t ed25519 -C "socoolbear"` → 공개키를 GitHub SSH key 에 등록

### 작업 디렉토리

```shell
mkdir -p ~/code ~/.local/bin
```

### Zsh + oh-my-zsh

`make sync` 시 자동 설치되며, 다음 플러그인을 함께 설치합니다.
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`

### 터미널 세팅

- Kitty + Nerd Font (JetBrainsMono 권장)
- SSH 원격 tmux 256색 이슈: `~/.ssh/config` 에 `SetEnv TERM=xterm` 추가

### 선택 사항

- 키 길게 누름 시 액센트 팝업 비활성화

  ```shell
  defaults write -g ApplePressAndHoldEnabled -bool false
  ```
- oh-my-zsh
  - agnoster 테마 [멀티라인 설정](https://gist.github.com/socoolbear/d59447cfaffc24ee914e27fe3019cd81)
- Karabiner-Elements
- git include 분리 (work / personal 계정) — [install-note 참조](docs/install-note.md#git)

## 설치

```shell
git clone https://github.com/socoolbear/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make sync
```

### Make 명령어

| 명령 | 설명 |
|------|------|
| `make sync` | 심볼릭 링크 생성 (oh-my-zsh, oh-my-tmux 자동 설치 포함) |
| `make clean` | 모든 심볼릭 링크 제거 |
| `make backup` | 기존 dotfiles 를 `~/backup_dotfiles/` 에 백업 |

## 더 보기

- [설치 후 작업 노트](docs/install-note.md)
- [홈 디렉토리에서 옮길 파일 가이드](docs/migration-files.md)
- [AI 에이전트 가이드](AGENTS.md)
