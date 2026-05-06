# AGENTS.md

> AI 에이전트가 이 저장소를 이해하고 작업하기 위한 가이드
> 코딩 스타일은 `claude/rules/coding-style.md`, 워크플로우/언어/환경은 `~/.claude/AGENTS.md` 참조

## 프로젝트 개요

macOS 개발 환경을 위한 개인 dotfiles 저장소. Makefile 기반 심볼릭 링크 관리를 통해 설정 파일들을 한 곳에서 관리합니다.

## 명령어

```bash
make fresh       # 새 장비용: brew + sync + mise + npm + macos 일괄
make update      # 일상 동기화: brew + sync
make brew        # Brewfile 적용 (코어 CLI 도구)
make brew-apps   # Brewfile.apps 적용 (GUI 앱 + Mac App Store)
make sync        # 심볼릭 링크 생성 (oh-my-zsh, oh-my-tmux 자동 설치)
make mise        # mise/config.toml 의 글로벌 도구 설치 (node, go)
make npm         # NPM globals (npm/globals.txt + @nestjs/cli)
make macos       # macOS 시스템 기본값 (macos/defaults.sh)
make bootstrap   # 1-shot 부트스트랩 (Xcode CLT, Homebrew 설치 포함)
make clean       # 심볼릭 링크 제거
make backup      # 기존 dotfiles 백업 (~/backup_dotfiles/)
make help        # 명령어 목록 출력
```

## 상세 가이드

| 주제 | 참조 |
|------|------|
| 디렉토리 구조 + 심볼릭 링크 매핑 + `.claude/` 구조 | `@docs/structure.md` |
| Makefile 동작 원리 + claude/ 하위 구성 + backup 한계 | `@docs/architecture.md` |
| Bootstrap / 새 장비 설치 노트 + 홈 디렉토리에서 옮길 파일 | `@docs/install-note.md` |

> 위 표의 `@docs/...` 항목은 해당 작업에 진입할 때 **반드시 먼저 읽어야 함** 을 의미합니다.

## 작업 완료 체크리스트

- [ ] 요청된 모든 변경사항이 반영되었는가?
- [ ] `make sync` 가 정상 동작하는가? (멱등성 확인)
- [ ] 새로운 심볼릭 링크 추가 시 `make clean` 에도 대응 줄을 추가했는가?
- [ ] 기존 심볼릭 링크가 영향받지 않았는가?
