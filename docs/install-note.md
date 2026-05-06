# 설치 후 작업 노트

새 macOS 장치 셋업 시 dotfiles 설치 외에 **수동으로 처리할 항목들**.

> 패키지/도구 설치는 `Brewfile` (`make brew`) 와 `Brewfile.apps` (`make brew-apps`) 가 처리합니다. 본 문서는 자동화되지 않는 잔여 작업만 다룹니다.

## 참고

- [홈 디렉토리에서 옮길 파일 가이드](./migration-files.md)

## GUI 앱

후보군은 `Brewfile.apps` 에 카테고리별 (협업/개발/AI/유틸/브라우저/네트워크 등) 로 주석 처리되어 있습니다. 새 장비에서 필요한 항목의 주석을 해제한 뒤:

```bash
make brew-apps    # mas 항목 사용 시 사전에 App Store 로그인 필요
```

## 셋업 작업

### Shell

- `~/.zsh_history` 마이그레이션은 [migration-files 의 비교 표](./migration-files.md#zsh-history-동기화-옵션-비교) 참조 (atuin 권장).
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
