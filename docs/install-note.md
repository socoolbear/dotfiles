# 설치 후 작업 노트

새 macOS 장치 셋업 시 dotfiles 설치 외에 수동으로 처리할 항목들.

## 참고

- [홈 디렉토리에서 옮길 파일 가이드](./migration-files.md)

## 필수 앱

- **업무/협업**: Slack, Notion, Zoom, Discord
- **개발**: JetBrains, Postman, Docker, K9s
- **AI**: Claude Code, Claude Desktop, ChatGPT Desktop
- **유틸**: Rectangle, Alfred, 1Password, RunCat
- **네트워크**: FortiClient (VPN)
- **브라우저/디자인**: Google Chrome, Figma
- **문서**: Obsidian
- **메신저**: KakaoTalk

## 터미널 도구

- **코어 대체**: `ripgrep`, `fd`, `bat`, `eza`, `zoxide`
- **검색 / 히스토리**: `fzf`, `atuin`
- **데이터 처리**: `jq`, `yq`, `httpie`
- **코드 검색 / 품질**: `ast-grep`, `difftastic`, `shellcheck`, `shfmt`, `ruff`
- **Git / TUI**: `gh`, `git-delta`, `lazygit`, `yazi`
- **프롬프트**: `starship`

## 셋업 작업

### Shell

- 이전 장치의 `~/.zsh_history` 복사 (또는 atuin 동기화)

### Git

- 전역 user.name / user.email 설정
- 계정 분리: `~/.gitconfig` 의 `IncludeIf` 사용 (work / personal)

### 앱별 설정

- **Alfred**: 플러그인/Workflow 설정
- **Obsidian**: vault 설정
- **FortiClient**: VPN 프로필
- **JetBrains**: 터미널 폰트 (JetBrains Mono 13pt)

### JetBrains 단축키 충돌 방지

- `cmd + shift + A` 충돌 해결
- 설정 → 키보드 단축키 → 서비스 → 텍스트 → "터미널에서 man 페이지 인덱스 검색" off

### GitHub Copilot

- [copilot 디렉토리](../copilot) 의 인스트럭션 파일을 프로젝트 루트의 `.github/` 로 복사

### Claude

- claude-desktop, claude-code 설정 동기화
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
