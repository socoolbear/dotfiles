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

`Brewfile.apps` 의 GUI 앱은 활성/주석 두 가지로 관리됩니다 — 평소 쓰는 앱은 주석 해제 상태로 자동 설치, 머신별 선택 앱은 주석 처리해두고 필요할 때만 풉니다.

> **Mac App Store 앱 (KakaoTalk, RunCat 등) 은 수동 설치를 권장합니다.** mas-cli 는 Big Sur+ 에서 "이미 다운받은 적 있는 앱" 의 install 에 실패합니다 (Apple private API 제한). App Store 에서 직접 다운로드하세요.

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
- **atuin login** (sync 사용 시): `atuin login -u <username>` → 비밀번호 + sync key 입력. 이어서 `atuin sync` 로 기존 히스토리 가져오기. sync key 는 기존 머신에서 `atuin key` 로 확인.

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

### mise

`make sync` / `make mise` 가 `mise trust ~/.dotfiles/mise/config.toml` 을 자동 실행합니다 (mise 는 새 config 를 untrusted 로 간주해서 셸 시작 시마다 에러를 띄움). 수동으로 해결해야 할 경우:

```shell
mise trust ~/.dotfiles/mise/config.toml
```

### 앱별 설정

- **Alfred 5**: 플러그인 / Workflow 설정
  - 시스템 설정 → 키보드 단축키 → 서비스 → 텍스트 → Spotlight 검색 보기 → option+cmd+space 로 변경
  - Alfred 단축키 cmd+space 로 변경
  - features > clipboard history > shift+cmd+v 로 변경 및 기타 체크박스 활성
  - **Workflow 설치**: `.alfredworkflow` 파일을 더블클릭하면 Alfred 가 import 다이얼로그 표시
    - **DeepL Translate**: [alexanderwillner/deepl-translate](https://alfred.app/workflows/alexanderwillner/deepl-translate/) 다운로드 → DeepL API key 등록
- **Obsidian**: vault 설정
- **JetBrains**:
  - 터미널 폰트 (JetBrains Mono 13pt)
  - Claude Code plugin: `claude --dangerously-skip-permissions`
  - IdeaVim plugin
  - `cmd + shift + A` 충돌 해결: 설정 → 키보드 단축키 → 서비스 → 텍스트 → "터미널에서 man 페이지 인덱스 검색" off
  - `cmd + esc` 안 눌리는 문제 해결: 설정 → 키보드 단축키 → 미션 컨트롤 → "게임 오버레이" off
- **Claude Code**:
  - Playwright MCP
- **ngrok**: `ngrok config add-authtoken <token>` 으로 인증 (`~/.config/ngrok/ngrok.yml` 생성). 토큰은 [dashboard.ngrok.com](https://dashboard.ngrok.com/get-started/your-authtoken) 에서 확인
- **BetterDisplay**: 첫 실행 시 화면 녹화 권한 요청 승인 (시스템 설정 → 개인정보 보호 및 보안 → 화면 녹화). Pro 라이선스 키 있으면 메뉴바 아이콘 → Settings → License 에서 입력
- **VS Code / Cursor**: dotfiles 외부 항목
  - `~/Library/Application Support/Code/User/settings.json`
  - `~/Library/Application Support/Code/User/keybindings.json`
  - 확장: `code --list-extensions > extensions.txt`

### Claude

`make sync` 가 `~/.claude/` 하위 (settings.json, CLAUDE.md, AGENTS.md, rules, scripts, docs, commands, skills) 와 `~/.mcp.json` 을 심링크합니다. `claude/skills/*/` 는 와일드카드로 자동 발견되어 디렉토리 단위로 심링크됩니다 — `[ -L ]` 체크가 있어 dotfiles 에 없는 머신별 skill (예: 로컬에서만 만든 것) 은 보존됩니다.

plugin 관리는 `/plugin` 명령어로 일원화 — 변경사항은 committed `settings.json` 에 자동 기록되어 모든 장비에 동기화됩니다 (host 가 없는 plugin 은 inert 상태로 무해). `~/.claude/settings.local.json` 은 시크릿/머신별 permission 같은 진짜 머신별 항목에만 사용합니다.

프로젝트 로컬 skill (`.claude/skills/`, dotfiles repo 안에서만 트리거):

- `setup-env` — dotfiles 의 환경 세팅 워크플로우 진입점. "환경 세팅해줘", "dotfiles 동기화", "make update" 같은 표현으로 트리거됩니다.

## 선택 사항

- **macOS 시스템 기본값**: `make macos` 가 처리 (`macos/defaults.sh`)
- **oh-my-zsh agnoster 테마**: [멀티라인 설정 gist](https://gist.github.com/socoolbear/d59447cfaffc24ee914e27fe3019cd81)
- **Karabiner-Elements**: `Brewfile.apps` 의 cask 주석 해제. 설정은 `karabiner/` 가 자동 심링크
