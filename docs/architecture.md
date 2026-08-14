# 아키텍처

## Makefile 기반 관리

- **단일 파일**: `[ -L ... ] || ln -sf` 패턴으로 멱등 심볼릭 링크
- **디렉토리**: `rm -rf` 후 `ln -sf` 패턴으로 전체 교체
- **프레임워크**: oh-my-zsh, oh-my-tmux 자동 설치

## Homebrew 예약 갱신 (launchd)

Homebrew 갱신을 **정해진 시각에만** 수행합니다. 작업 중인 `brew` 명령이 자동 갱신에 붙잡히거나, 로그인할 때마다 갱신이 시작되는 일을 없애기 위한 구성입니다.

- `zsh/zshrc` 의 `HOMEBREW_NO_AUTO_UPDATE=1` — brew 명령이 스스로 갱신하지 않음 (기존 `HOMEBREW_AUTO_UPDATE_SECS` 대체)
- `launchd/com.socoolbear.brew-scheduled-update.plist` — **예약 시각 매일 04:30** (`StartCalendarInterval`), `RunAtLoad` 는 꺼둠
- `scripts/brew-scheduled-update.sh` — `brew update` → `brew upgrade` (formula + cask) → `brew cleanup --prune=30`

### 지연 실행 처리

launchd 는 예약 시각에 맥이 잠들어 있었으면 **깨어난 직후** 작업을 실행합니다. 이때 실제 실행 시각이 예약 시각과 크게 어긋날 수 있어, 스크립트가 실행 시각을 스스로 검사합니다.

| 실행 시점 | 동작 |
|------|------|
| 실행 허용 구간 (03:00~08:00) 안 | 실행 |
| 허용 구간 밖의 지연 실행 | 건너뛰고 다음 예약 대기 |
| 마지막 실행 후 7 일 초과 (`OVERDUE_DAYS`) | 허용 구간 무시하고 1 회 실행 — 갱신이 무한정 밀리는 것 방지 |
| 실행 기록이 아예 없을 때 (최초 등록 직후) | 기록만 초기화하고 다음 예약으로 넘김 — 등록하자마자 대규모 업그레이드 방지 |

허용 구간은 스크립트의 `RUN_WINDOW_START` / `RUN_WINDOW_END` 로 정합니다. **예약 시각(plist)을 바꾸면 이 구간도 함께 옮겨야** 정상 실행이 건너뛰어지지 않습니다.

### 운영

- 상태 파일: `~/.local/state/brew-scheduled-update/last-run` (마지막 실행 시각)
- 로그: `~/Library/Logs/brew-scheduled-update.log` (1MB 초과 시 `.1` 로 1 회 로테이션)
- 예약을 기다리지 않고 즉시 실행 / 로그 확인: `make brew-scheduled-update`, `make brew-scheduled-update-log`
- 예약 등록은 심링크만으로 되지 않으므로 `make sync` 가 `launchctl bootout` → `bootstrap` 으로 재등록합니다 (멱등). `make clean` 은 `bootout` 후 심링크를 제거합니다.
- 등록 상태 확인: `launchctl print gui/$(id -u)/com.socoolbear.brew-scheduled-update`

> 과거에 쓰던 `brew autoupdate` (homebrew/autoupdate 탭) 는 로그인 시 + 24시간 간격이라 실행 시각을 지정할 수 없어 제거했습니다. 새 장비에서 실수로 다시 깔았다면 `brew autoupdate delete` 로 지우세요.

## oh-my-tmux 주의사항

- `tmux.conf` 는 oh-my-tmux 가 관리 (수정 금지)
- `tmux.conf.local` 만 커스터마이징
- 위치: `~/.config/tmux/` (XDG 표준)

## claude/ 하위 구성

- `claude/settings.json` — Claude Code 글로벌 설정 (hooks, 권한, 환경변수)
- `claude/.mcp.json` — MCP 서버 정의 (홈 루트 `~/.mcp.json` 으로 링크)
- `claude/CLAUDE.md` / `claude/AGENTS.md` — 글로벌 인스트럭션
- `claude/rules/` — 자동 로드되는 규칙 모음 (예: `coding-style.md`)
- `claude/scripts/` — Hook 등에서 호출하는 유틸 스크립트 (`statusline-command.sh`, `enforce-plan-review.sh`, `team-cleanup-check.sh`)
- `claude/docs/` — `claude/AGENTS.md` 가 `@docs/...` 로 참조하는 상세 가이드 (워크플로우, 피드백 라우팅 등)
- `claude/commands/` — 슬래시 명령어 정의 (`*.md` 와일드카드 자동 발견)
- `claude/skills/` — Claude Code skill 정의 (`*/` 디렉토리 단위 자동 발견, 머신별 실디렉토리는 보존)
- `claude/agents/` — 팀메이트/서브에이전트 정의 (`*.md` 와일드카드 자동 발견, 머신별 실파일은 보존)

## `make backup` 의 한계

`make backup` 은 zsh, vim, idea, tmux, git, ghostty, karabiner, mise 만 백업합니다. 다음은 백업 대상이 아니므로 필요시 직접 처리:

- `~/.claude/` (settings.json 등)
- `~/.mcp.json`
