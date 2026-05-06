# Dotfiles

macOS 개발 환경을 위한 개인 dotfiles. Makefile 기반 심볼릭 링크로 관리합니다.

## 한 줄 셋업 (새 장비)

```shell
curl -fsSL https://raw.githubusercontent.com/socoolbear/dotfiles/master/bootstrap.sh | bash
```

위 스크립트는 Xcode CLT → Homebrew → dotfiles clone → `make fresh` (brew + sync + mise + npm + macos) 순으로 실행합니다.

## 사전 준비

### Homebrew

```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 패키지 / 앱 (Brewfile)

코어 CLI 도구는 `Brewfile`, GUI 앱은 `Brewfile.apps` 로 분리되어 선언되어 있습니다.

```shell
make brew         # 코어 도구 (formula + tap)
make brew-apps    # GUI 앱 (cask + mas) — 새 장비에서만 선택적으로 실행
```

`Brewfile.apps` 의 GUI 앱 후보들은 주석 처리되어 있으니 새 장비에서 필요한 항목만 주석을 해제한 뒤 실행하세요. Mac App Store 항목 (`mas`) 사용 시 사전에 App Store 로그인이 필요합니다.

다른 Nerd Font 가 필요하면 [getnf](https://github.com/ronniedroid/getnf) 사용.

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

- **macOS 시스템 기본값**: `make macos` 가 처리 (`macos/defaults.sh`)
- **oh-my-zsh agnoster 테마**: [멀티라인 설정 gist](https://gist.github.com/socoolbear/d59447cfaffc24ee914e27fe3019cd81)
- **Karabiner-Elements**: `Brewfile.apps` 의 cask 주석 해제. 설정은 `karabiner/` 가 자동 심링크
- **Git include 분리** (work / personal): `~/.gitconfig_local` 에 작성 — [install-note 참조](docs/install-note.md#git)
- **Claude Code skill**: `make sync` 가 `claude/skills/*/` 를 `~/.claude/skills/` 로 자동 심링크. 기본 제공되는 `setup-env` skill 은 새 대화에서 "환경 세팅해줘", "dotfiles 동기화" 같은 표현으로 트리거되어 적절한 `make` 타겟을 안내·실행합니다.

## 설치 (수동)

```shell
git clone https://github.com/socoolbear/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make fresh
```

### Make 명령어

| 명령 | 설명 |
|------|------|
| `make fresh` | 새 장비용: `brew + sync + mise + npm + macos` 일괄 실행 |
| `make update` | 일상 동기화: `brew + sync` 만 |
| `make brew` | `Brewfile` 적용 (코어 CLI 도구) |
| `make brew-apps` | `Brewfile.apps` 적용 (GUI 앱 + Mac App Store) |
| `make sync` | 심볼릭 링크 생성 (oh-my-zsh, oh-my-tmux 자동 설치 포함) |
| `make mise` | `mise/config.toml` 의 글로벌 도구 설치 (node, go) |
| `make npm` | NPM globals 설치 (`npm/globals.txt` 매니페스트 + `@nestjs/cli`) |
| `make macos` | macOS 시스템 기본값 적용 (`macos/defaults.sh`) |
| `make bootstrap` | 새 장비 1-shot 부트스트랩 (Xcode CLT + Homebrew 설치 포함) |
| `make clean` | 모든 심볼릭 링크 제거 |
| `make backup` | 기존 dotfiles 를 `~/backup_dotfiles/` 에 백업 |
| `make help` | 본 명령어 목록을 터미널에 출력 |

## 더 보기

- [설치 후 작업 노트](docs/install-note.md)
- [홈 디렉토리에서 옮길 파일 가이드](docs/migration-files.md)
- [AI 에이전트 가이드](AGENTS.md)
