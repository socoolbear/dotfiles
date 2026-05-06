# 새 장치로 옮길 파일 가이드

홈 디렉토리에 누적된 "기억된 값들" (history, config, credentials 등) 중 새 장치로 옮길 가치가 있는 파일 목록과 권장 처리 방식.

> **판단 기준**: 민감 정보 포함 여부 + 자동 재생성 가능 여부

## ✅ 옮겨도 안전 — repo 에 직접 추가 가능

| 파일 | 용도 | 비고 |
|------|------|------|
| `~/.ssh/config` | SSH host alias, 포트, ProxyJump 등 | 평문이지만 hostname 정도라 OK |
| `~/.gitconfig_local` | Git user.email / `includeIf` (호스트별) | 본 dotfiles 의 `git/gitconfig` 가 `[include]` 로 자동 로드 |
| `~/.aws/config` | profile 이름·region | credentials 와 분리되어 있어 안전 |

> `~/.gitconfig` 자체는 본 dotfiles 의 `git/gitconfig` 로 심링크되므로 옮기지 말 것. 호스트별 user.email 은 `~/.gitconfig_local` 에 작성합니다 ([install-note](./install-note.md#git) 참조).

## ⚠️ 민감 정보 — repo 추가 시 선별/마스킹 필요

| 파일 | 위험 요소 | 권장 방식 |
|------|----------|----------|
| `~/.zsh_history` | 토큰·비밀번호·내부 호스트명 평문 | git 비추천. atuin 또는 iCloud symlink |
| `~/.ssh/known_hosts` | 접속한 서버 핑거프린트 노출 | private repo 만, 아니면 옮기지 말 것 |
| `~/.npmrc` | `_authToken` 포함 가능 | 토큰 제거 후 template 만 |
| `~/.aws/credentials` | **절대 금지** | 1Password CLI (`op`) 로 관리 |
| `~/.kube/config` | 클러스터 접근 토큰 | 절대 금지 |
| `~/.docker/config.json` | registry credentials | 비추천 |

## 🔄 옮길 필요 없음 — 자동 재생성됨

새 장치에서 사용하면 알아서 채워지는 파일들:

- `~/.bash_history`
- `~/.viminfo`
- `~/.psql_history`, `~/.mysql_history`, `~/.rediscli_history`, `~/.php_history`, `~/.python_history`

`~/.gnupg/` 은 키 자체는 백업 필요하지만 1Password 나 별도 안전한 곳에. trustdb 는 키만 있으면 재생성됩니다.

## 💡 추가로 옮길 가치 있는 것들

> Homebrew 패키지 목록과 macOS 시스템 설정은 본 dotfiles 가 이미 처리합니다 (`Brewfile` / `make macos`). 아래는 dotfiles 외부 항목.

### VS Code / Cursor 설정

- `~/Library/Application Support/Code/User/settings.json`
- `~/Library/Application Support/Code/User/keybindings.json`
- 확장: `code --list-extensions > extensions.txt`

### SSH 키

1Password SSH agent 사용 시 키는 1Password 가 관리. dotfiles 에는 `~/.ssh/config` 만 두면 충분.

## zsh history 동기화 옵션 비교

| 방법 | 보안 | 검색 | 멀티 디바이스 | 셋업 |
|------|------|------|--------------|------|
| **atuin** | E2E 암호화 | fuzzy + 통계 | ✅ | `brew install atuin` |
| **iCloud symlink** | macOS 디스크 암호화만 | 기본 | △ (충돌 가능) | symlink 한 줄 |
| **private git repo** | repo 권한에 의존 | 기본 | ✅ (충돌 잦음) | cron 설정 필요 |
| **수동 복사** | - | - | 1회성 | `scp` |
