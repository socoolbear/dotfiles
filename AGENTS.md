# AGENTS.md

> AI 에이전트가 이 저장소를 이해하고 작업하기 위한 가이드
> 코딩 스타일은 `~/.claude/workstyle/coding-style.md`, 언어·용어·환경 (공용) 은 `~/.claude/workstyle/AGENTS.md`, Claude Code 워크플로우는 `~/.claude/workstyle/workflow-table.md` 참조 (workstyle 플러그인의 글 — 고칠 때는 그 파일을 고치고 플러그인 저장소에 커밋)

## 프로젝트 개요

macOS 개발 환경을 위한 개인 dotfiles 저장소. Makefile 기반 심볼릭 링크 관리를 통해 설정 파일들을 한 곳에서 관리합니다.

## 명령어

```bash
make fresh       # 새 장비용: brew + sync + mise + npm + macos 일괄
make update      # 일상 동기화: brew + sync
make brew        # Brewfile 적용 (코어 CLI 도구)
make brew-apps   # Brewfile.apps 적용 (GUI 앱 + Mac App Store)
make brew-cleanup        # Brewfile 에 없는 패키지 출력 (dry-run)
make brew-cleanup-force  # Brewfile 에 없는 패키지 실제 제거
make brew-scheduled-update     # Homebrew 예약 갱신을 지금 즉시 실행 (예약 대기 없이)
make brew-scheduled-update-log # 예약 갱신 최근 로그 확인
make machine-check     # 주 1회 장비 점검 (launchd, dotfiles-doctor 의 machine.sh) 을 지금 즉시 실행 — FAIL · WARN 이 있으면 메일
make machine-check-log # 장비 점검 최근 로그 확인
make auto-update       # dotfiles · cc-marketplace 체크아웃 · 플러그인 자동 갱신 (launchd 매일 11:00) 을 지금 즉시 실행 — 안전할 때만 받음
make auto-update-log   # 자동 갱신 상태 (대상별 최신 / 받음 / 손 필요) 와 최근 로그 확인
make sync        # 심볼릭 링크 생성 (oh-my-zsh, oh-my-tmux 자동 설치)
make mise        # mise/config.toml 의 글로벌 도구 설치 (node, go)
make npm         # NPM globals (npm/globals.txt + @nestjs/cli)
make macos       # macOS 시스템 기본값 (macos/defaults.sh)
make sleepguard  # 잠자기 방지 셋업 (sudoers 룰 + SwiftBar 폴더 지정, sudo 필요 · 새 장비 1회)
make bootstrap   # 1-shot 부트스트랩 (Xcode CLT, Homebrew 설치 포함)
make clean       # 심볼릭 링크 제거
make backup      # 호스트 로컬 데이터 백업 (~/backup_dotfiles/)
make help        # 명령어 목록 출력
```

## 상세 가이드

| 주제 | 참조 |
|------|------|
| 디렉토리 구조 + 심볼릭 링크 매핑 + `.claude/` 구조 | `@docs/structure.md` |
| Makefile 동작 원리 + claude/ 하위 구성 + backup 한계 | `@docs/architecture.md` |
| 새 장비 셋업 (사전 준비 + 후속 작업: Homebrew, SSH, Git, Claude, 앱별 설정) | `@docs/setup.md` |
| 기존 장비에서 옮길 파일 + zsh history 동기화 옵션 | `@docs/migration.md` |
| 프로젝트별 `.env` 관리 (1Password CLI) | `@docs/secrets.md` |
| GitHub 계정 분리 (side 계정 적용 범위) | `@docs/github-accounts.md` |

> 위 표의 `@docs/...` 항목은 해당 작업에 진입할 때 **반드시 먼저 읽어야 함** 을 의미합니다.

## 작업 완료 체크리스트

- [ ] 요청된 모든 변경사항이 반영되었는가?
- [ ] `make sync` 가 정상 동작하는가? (멱등성 확인)
- [ ] 새로운 심볼릭 링크 추가 시 `make clean` 에도 대응 줄을 추가했는가?
- [ ] launchd 예약 작업은 `launchd/` 에 틀 (`@HOME@/.local/bin/<이름>` 직접 실행) 만 두었는가? (`make sync` 가 만들고 걸며, 틀을 지우면 내리고 치운다 — `docs/architecture.md`)
- [ ] 기존 심볼릭 링크가 영향받지 않았는가?
