# Dotfiles

macOS 개발 환경을 위한 개인 dotfiles. Makefile 기반 심볼릭 링크로 관리합니다.

## 한 줄 셋업 (새 장비)

```shell
curl -fsSL https://raw.githubusercontent.com/socoolbear/dotfiles/master/bootstrap.sh | bash
```

위 스크립트는 Xcode CLT → Homebrew → dotfiles clone → `make fresh` (brew + sync + mise + npm + macos) 순으로 실행합니다.

## 수동 설치

```shell
git clone https://github.com/socoolbear/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make fresh
```

새 장비의 사전 준비 (Homebrew, SSH, 작업 디렉토리 등) 와 후속 셋업 작업은 [docs/setup.md](docs/setup.md) 참조.

## Make 명령어

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

- [새 장비 셋업 가이드](docs/setup.md) — Homebrew, SSH, Zsh, Git, Claude 등 사전 / 후속 작업
- [기존 장비에서 옮길 파일](docs/migration.md) — 마이그레이션 판단표 + zsh history 옵션
- [프로젝트별 .env 관리](docs/secrets.md) — 1Password CLI 패턴
- [디렉토리 구조 + 심볼릭 링크 매핑](docs/structure.md)
- [아키텍처 (Makefile 동작 원리)](docs/architecture.md)
- [AI 에이전트 가이드](AGENTS.md)
