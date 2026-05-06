# 설치 후 작업 노트

새 macOS 장치 셋업 시 dotfiles 설치 외에 **수동으로 처리할 항목들**.

> 패키지/도구 설치는 `Brewfile` (`make brew`) 와 `Brewfile.apps` (`make brew-apps`) 가 처리합니다. 본 문서는 자동화되지 않는 잔여 작업만 다룹니다.

## 홈 디렉토리에서 옮길 파일

홈 디렉토리에 누적된 "기억된 값들" (history, config, credentials 등) 중 새 장치로 옮길 가치가 있는 파일 목록과 권장 처리 방식.

> **판단 기준**: 민감 정보 포함 여부 + 자동 재생성 가능 여부

### ✅ 옮겨도 안전 — repo 에 직접 추가 가능

| 파일 | 용도 | 비고 |
|------|------|------|
| `~/.ssh/config` | SSH host alias, 포트, ProxyJump 등 | 평문이지만 hostname 정도라 OK |
| `~/.gitconfig_local` | Git user.email / `includeIf` (호스트별) | 본 dotfiles 의 `git/gitconfig` 가 `[include]` 로 자동 로드 |
| `~/.aws/config` | profile 이름·region | credentials 와 분리되어 있어 안전 |

> `~/.gitconfig` 자체는 본 dotfiles 의 `git/gitconfig` 로 심링크되므로 옮기지 말 것. 호스트별 user.email 은 `~/.gitconfig_local` 에 작성합니다 (아래 [Git](#git) 섹션 참조).

### ⚠️ 민감 정보 — repo 추가 시 선별/마스킹 필요

| 파일 | 위험 요소 | 권장 방식 |
|------|----------|----------|
| `~/.zsh_history` | 토큰·비밀번호·내부 호스트명 평문 | git 비추천. atuin 또는 iCloud symlink |
| `~/.ssh/known_hosts` | 접속한 서버 핑거프린트 노출 | private repo 만, 아니면 옮기지 말 것 |
| `~/.npmrc` | `_authToken` 포함 가능 | 토큰 제거 후 template 만 |
| `~/.aws/credentials` | **절대 금지** | 1Password CLI (`op`) 로 관리 |
| `~/.kube/config` | 클러스터 접근 토큰 | 절대 금지 |
| `~/.docker/config.json` | registry credentials | 비추천 |

### 🔄 옮길 필요 없음 — 자동 재생성됨

새 장치에서 사용하면 알아서 채워지는 파일들:

- `~/.bash_history`
- `~/.viminfo`
- `~/.psql_history`, `~/.mysql_history`, `~/.rediscli_history`, `~/.php_history`, `~/.python_history`

`~/.gnupg/` 은 키 자체는 백업 필요하지만 1Password 나 별도 안전한 곳에. trustdb 는 키만 있으면 재생성됩니다.

### 💡 추가로 옮길 가치 있는 것들

> Homebrew 패키지 목록과 macOS 시스템 설정은 본 dotfiles 가 이미 처리합니다 (`Brewfile` / `make macos`). 아래는 dotfiles 외부 항목.

#### VS Code / Cursor 설정

- `~/Library/Application Support/Code/User/settings.json`
- `~/Library/Application Support/Code/User/keybindings.json`
- 확장: `code --list-extensions > extensions.txt`

#### SSH 키

1Password SSH agent 사용 시 키는 1Password 가 관리. dotfiles 에는 `~/.ssh/config` 만 두면 충분.

### zsh history 동기화 옵션 비교

| 방법 | 보안 | 검색 | 멀티 디바이스 | 셋업 |
|------|------|------|--------------|------|
| **atuin** | E2E 암호화 | fuzzy + 통계 | ✅ | `brew install atuin` |
| **iCloud symlink** | macOS 디스크 암호화만 | 기본 | △ (충돌 가능) | symlink 한 줄 |
| **private git repo** | repo 권한에 의존 | 기본 | ✅ (충돌 잦음) | cron 설정 필요 |
| **수동 복사** | - | - | 1회성 | `scp` |

## GUI 앱

후보군은 `Brewfile.apps` 에 카테고리별 (협업/개발/AI/유틸/브라우저/네트워크 등) 로 주석 처리되어 있습니다. 새 장비에서 필요한 항목의 주석을 해제한 뒤:

```bash
make brew-apps    # mas 항목 사용 시 사전에 App Store 로그인 필요
```

## 셋업 작업

### Shell

- `~/.zsh_history` 마이그레이션은 위 [zsh history 동기화 옵션 비교](#zsh-history-동기화-옵션-비교) 참조 (atuin 권장).
- 시크릿 환경 변수: `cp zsh/private.export.example ~/.private-exports` 후 토큰 입력 (NTFY/EXA/GitHub 등). zshrc 가 자동 로드합니다.

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

- **Alfred**: 플러그인/Workflow 설정
- **Obsidian**: vault 설정
- **JetBrains**:
  - 터미널 폰트 (JetBrains Mono 13pt)
  - `cmd + shift + A` 충돌 해결: 설정 → 키보드 단축키 → 서비스 → 텍스트 → "터미널에서 man 페이지 인덱스 검색" off

### Claude

`make sync` 가 `~/.claude/` 하위 (settings.json, CLAUDE.md, AGENTS.md, rules, scripts, docs, commands, skills) 와 `~/.mcp.json` 을 심링크합니다. `claude/skills/*/` 는 와일드카드로 자동 발견되어 디렉토리 단위로 심링크됩니다 — `[ -L ]` 체크가 있어 dotfiles 에 없는 머신별 skill (예: 로컬에서만 만든 것) 은 보존됩니다.

기본 제공 skill:

- `setup-env` — dotfiles 의 환경 세팅 워크플로우 진입점. "환경 세팅해줘", "dotfiles 동기화", "make update" 같은 표현으로 트리거됩니다.

추가 자료:

- [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework)
- [claude-code-requirements-builder](https://github.com/rizethereum/claude-code-requirements-builder)

## 프로젝트별 `.env` 관리 (1Password CLI)

```shell
brew install 1password-cli
op signin
```

### 새 환경 파일 등록

```shell
op item create --vault="my-vault" --category="Secure Note" \
  --title="myproject-env" \
  ENV_CONTENT="$(cat .env)"
```

### 기존 환경 파일 가져오기

```shell
op item get "myproject-env" --vault="my-vault" --format json --reveal \
  | jq -r '.fields[] | select(.label=="ENV_CONTENT") | .value' > .env
```

### 환경 파일 갱신

```shell
op item edit "myproject-env" --vault="my-vault" \
  ENV_CONTENT="$(cat .env)"
```
