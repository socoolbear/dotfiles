# 새 장비 셋업 가이드

자동화되지 않는 사전 준비 + 후속 셋업 작업. 패키지 설치 자체는 `make brew` / `make brew-apps` 가 처리합니다.

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

`Brewfile.apps` 의 GUI 앱 후보들은 카테고리별 (협업/개발/AI/유틸/브라우저/네트워크 등) 로 주석 처리되어 있습니다. 새 장비에서 필요한 항목만 주석을 해제한 뒤 실행하세요. Mac App Store 항목 (`mas`) 사용 시 사전에 App Store 로그인이 필요합니다.

다른 Nerd Font 가 필요하면 [getnf](https://github.com/ronniedroid/getnf) 사용.

### SSH

- **권장**: 1Password SSH agent 활성화 → 키는 1Password 가 관리, dotfiles 에는 `~/.ssh/config` 만 두면 충분
- **대안**: `ssh-keygen -t ed25519 -C "socoolbear"` → 공개키를 GitHub SSH key 에 등록

### 작업 디렉토리

```shell
mkdir -p ~/code ~/.local/bin
```

### Zsh + oh-my-zsh

`make sync` 시 자동 설치되며, 다음 플러그인을 함께 설치합니다.

- `zsh-autosuggestions`
- `zsh-syntax-highlighting`

### 터미널

- Ghostty + Nerd Font (JetBrainsMono 권장)
- SSH 원격 tmux 256색 이슈: `~/.ssh/config` 에 `SetEnv TERM=xterm` 추가

## 셋업 작업

### Shell

- 시크릿 환경 변수: `cp zsh/private.export.example ~/.private-exports` 후 토큰 입력 (NTFY/EXA/GitHub 등). zshrc 가 자동 로드합니다.
- `~/.zsh_history` 마이그레이션은 [migration.md 의 zsh history 섹션](migration.md#zsh-history-동기화-옵션-비교) 참조 (atuin 권장).

### Git

- `~/.gitconfig` 는 dotfiles 의 `git/gitconfig` 로 자동 심링크됩니다 (alias / delta / `[include]`).
- 호스트별 user.email / `includeIf` 는 `~/.gitconfig_local` 에 작성:

  ```
  [user]
      name = socoolbear
      email = socoolbear@gmail.com

  [includeIf "gitdir:~/code/work/"]
      path = ~/code/work/.gitconfig-work
  ```

- 기존 `~/.gitconfig` 가 실파일이면 `make sync` 가 마이그레이션 안내 후 중단합니다:
  `mv ~/.gitconfig ~/.gitconfig_local && make sync`
- dotfiles `git/gitconfig` 는 `[commit] gpgsign = true` 를 설정합니다. 이 머신에 GPG 키가 없으면 `~/.gitconfig_local` 에 다음을 추가해 끄세요:

  ```
  [commit]
      gpgsign = false
  ```

### 앱별 설정

- **Alfred**: 플러그인 / Workflow 설정
- **Obsidian**: vault 설정
- **JetBrains**:
  - 터미널 폰트 (JetBrains Mono 13pt)
  - `cmd + shift + A` 충돌 해결: 설정 → 키보드 단축키 → 서비스 → 텍스트 → "터미널에서 man 페이지 인덱스 검색" off
- **VS Code / Cursor**: dotfiles 외부 항목
  - `~/Library/Application Support/Code/User/settings.json`
  - `~/Library/Application Support/Code/User/keybindings.json`
  - 확장: `code --list-extensions > extensions.txt`

### Claude

`make sync` 가 `~/.claude/` 하위 (settings.json, CLAUDE.md, AGENTS.md, rules, scripts, docs, commands, skills) 와 `~/.mcp.json` 을 심링크합니다. `claude/skills/*/` 는 와일드카드로 자동 발견되어 디렉토리 단위로 심링크됩니다 — `[ -L ]` 체크가 있어 dotfiles 에 없는 머신별 skill (예: 로컬에서만 만든 것) 은 보존됩니다.

프로젝트 로컬 skill (`.claude/skills/`, dotfiles repo 안에서만 트리거):

- `setup-env` — dotfiles 의 환경 세팅 워크플로우 진입점. "환경 세팅해줘", "dotfiles 동기화", "make update" 같은 표현으로 트리거됩니다.

## 선택 사항

- **macOS 시스템 기본값**: `make macos` 가 처리 (`macos/defaults.sh`)
- **oh-my-zsh agnoster 테마**: [멀티라인 설정 gist](https://gist.github.com/socoolbear/d59447cfaffc24ee914e27fe3019cd81)
- **Karabiner-Elements**: `Brewfile.apps` 의 cask 주석 해제. 설정은 `karabiner/` 가 자동 심링크
