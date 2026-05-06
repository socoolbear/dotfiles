# 아키텍처

## Makefile 기반 관리

- **단일 파일**: `[ -L ... ] || ln -sf` 패턴으로 멱등 심볼릭 링크
- **디렉토리**: `rm -rf` 후 `ln -sf` 패턴으로 전체 교체
- **프레임워크**: oh-my-zsh, oh-my-tmux 자동 설치

## oh-my-tmux 주의사항

- `tmux.conf` 는 oh-my-tmux 가 관리 (수정 금지)
- `tmux.conf.local` 만 커스터마이징
- 위치: `~/.config/tmux/` (XDG 표준)

## claude/ 하위 구성

- `claude/settings.json` — Claude Code 글로벌 설정 (hooks, 권한, 환경변수)
- `claude/.mcp.json` — MCP 서버 정의 (홈 루트 `~/.mcp.json` 으로 링크)
- `claude/CLAUDE.md` / `claude/AGENTS.md` — 글로벌 인스트럭션
- `claude/rules/` — 자동 로드되는 규칙 모음 (예: `coding-style.md`)
- `claude/scripts/` — Hook 등에서 호출하는 유틸 스크립트 (예: `notify.sh`, `statusline-command.sh`)
- `claude/docs/` — `claude/AGENTS.md` 가 `@docs/...` 로 참조하는 상세 가이드 (워크플로우, 피드백 라우팅 등)
- `claude/commands/` — 슬래시 명령어 정의

## `make backup` 의 한계

`make backup` 은 zsh, vim, idea, tmux, git, kitty, lvim, karabiner, mise 만 백업합니다. 다음은 백업 대상이 아니므로 필요시 직접 처리:

- `~/.config/ghostty/`
- `~/.config/opencode/`
- `~/.claude/` (settings.json 등)
- `~/.mcp.json`
