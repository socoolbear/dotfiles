# 프로젝트 구조 및 심볼릭 링크 매핑

## 디렉토리 개요

| 디렉토리 | 설명 | 대상 경로 | 자동 링크 |
|----------|------|-----------|-----------|
| `zsh/` | Zsh 설정 (oh-my-zsh) | `~/.zshrc`, `~/.zshenv` | ✅ |
| `vim/` | Vim/GVim 설정 | `~/.vimrc`, `~/.gvimrc` | ✅ |
| `idea/` | IdeaVim (JetBrains IDE) | `~/.ideavimrc` | ✅ |
| `tmux/` | Tmux 설정 (oh-my-tmux) | `~/.config/tmux/` | ✅ |
| `ghostty/` | Ghostty 터미널 | `~/.config/ghostty/` | ✅ |
| `karabiner/` | 키보드 리맵핑 | `~/.config/karabiner/` | ✅ |
| `swiftbar/` | SwiftBar 메뉴바 플러그인 (잠자기 방지 토글) | `~/.swiftbar-plugins/` | ✅ |
| `claude/` | Claude Code 글로벌 설정 | `~/.claude/` | ✅ (부분) |
| `mise/` | mise 글로벌 도구 매니페스트 (node, go 등) | `~/.config/mise/config.toml` | ✅ |
| `npm/` | 글로벌 NPM 패키지 매니페스트 (`make npm` 이 사용) | — | ❌ (repo 내부 참조) |
| `git/` | Git 설정 (alias / delta / include) | `~/.gitconfig`, `~/.gitignore_global` | ✅ |
| `launchd/` | launchd 예약 작업 정의 (Homebrew 예약 갱신 · 주 1회 장비 점검) | `~/Library/LaunchAgents/` | ✅ |
| `scripts/` | Makefile / launchd / MCP 설정이 호출하는 유틸 스크립트 | `~/.local/bin/` (일부) | ✅ (부분) |
| `mcp/` | MCP 서버 설정 파일 (dbhub 읽기 전용 설정) | `~/.config/dbhub/` | ✅ |
| `macos/` | macOS 시스템 기본값 스크립트 (`defaults.sh`, `make macos` 가 실행) | — | ❌ (스크립트 직접 실행) |
| `docs/` | 저장소 문서 (목록은 `AGENTS.md` 상세 가이드 표) | — | ❌ (문서 전용) |
| `.claude/` | 프로젝트 로컬 Claude 설정 | 로컬 전용 | — |
| `.github/` | GitHub Actions — 저장소 점검 (`check.yml` 이 `doctor.sh --repo-only` 를 push · PR · 주 1회 실행) | — | ❌ (GitHub 가 실행) |

## 심볼릭 링크 매핑 — 단일 파일

| Source | Target |
|--------|--------|
| `zsh/zshrc` | `~/.zshrc` |
| `zsh/zshenv` | `~/.zshenv` |
| `vim/vimrc` | `~/.vimrc` |
| `vim/gvimrc` | `~/.gvimrc` |
| `idea/ideavimrc` | `~/.ideavimrc` |
| `git/gitconfig` | `~/.gitconfig` |
| `git/gitignore_global` | `~/.gitignore_global` |
| `tmux/tmux.conf.local` | `~/.config/tmux/tmux.conf.local` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| (workstyle 플러그인) `~/.claude/workstyle/AGENTS.md` | `~/.codex/AGENTS.md` — 취향 규칙은 workstyle 플러그인이 `~/.claude/workstyle/` 에 내놓고 (`claude/CLAUDE.md` 가 홈 기준 경로로 import), Codex 링크는 그 폴더의 `AGENTS.md` 를 가리킨다. 비공개 배포 표 `~/.config/claude/deploy-targets.md` 와 장비 규칙 `~/.config/claude/local-rules.md` (원본은 워크스페이스 repo 의 `policy/`) 는 `make sync` 가 `~/.codex/AGENTS.override.md` 로 합친다. |
| `mise/config.toml` | `~/.config/mise/config.toml` |
| `scripts/brew-scheduled-update.sh` | `~/.local/bin/brew-scheduled-update` |
| `scripts/machine-check-scheduled.sh` | `~/.local/bin/dotfiles-machine-check` *(주 1회 장비 점검 — launchd 가 부른다)* |
| `scripts/sleepguard-toggle.sh` | `~/.local/bin/sleepguard` |
| `scripts/mcp-lazy.mjs` | `~/.local/bin/mcp-lazy` *(지연 시작 MCP 프록시 — `op://` 참조를 쓰는 아래 `mcp-secret-env` 가 거친다)* |
| `scripts/mcp-secret-env.sh` | `~/.local/bin/mcp-secret-env` *(비밀 값을 1Password · 키체인에서 꺼내 환경 변수 하나로 넘기고 MCP 서버를 실행 — 시험 DB MCP 와 운영 조회용 PostgreSQL · MySQL MCP 가 쓴다)* |
| `mcp/dbhub-pg-readonly.toml` | `~/.config/dbhub/pg-readonly.toml` *(dbhub PostgreSQL MCP 의 읽기 전용 설정 — 접속 정보는 `~/.claude.json` 의 env 로 받는다)* |
| `mcp/dbhub-mysql-readonly.toml` | `~/.config/dbhub/mysql-readonly.toml` *(dbhub MySQL MCP 의 읽기 전용 설정 — 운영 조회용 MySQL MCP 가 쓴다. 접속 정보는 `~/.claude.json` 의 env 로 받는다)* |
| `launchd/com.socoolbear.brew-scheduled-update.plist` | `~/Library/LaunchAgents/com.socoolbear.brew-scheduled-update.plist` |
| `launchd/com.socoolbear.dotfiles-machine-check.plist` | `~/Library/LaunchAgents/com.socoolbear.dotfiles-machine-check.plist` |

> 슬래시 명령 · 스킬 · 에이전트는 dotfiles 가 링크하지 않는다 — 작업 장치는 cc-marketplace 플러그인 (workstyle 등) 이 싣는다. `~/.local/bin/workstyle` · `loop-metrics` 는 `make sync` 가 부르는 `workstyle install` 이 만드는 실행 파일이다.

## 심볼릭 링크 매핑 — 디렉토리

| Source | Target |
|--------|--------|
| `ghostty/` | `~/.config/ghostty/` |
| `karabiner/` | `~/.config/karabiner/` |
| `swiftbar/` | `~/.swiftbar-plugins/` |
| `claude/scripts/` | `~/.claude/scripts/` |
| `claude/docs/` | `~/.claude/docs/` *(전역 교훈 `lessons.md`)* |
| `alfred/workflows/*/` | `~/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/<name>` *(와일드카드 자동 발견, 디렉토리 단위)* |

> `claude/mods/*/` (Claude Code mod) 는 링크하지 않고 `claude/settings.json` 의 `env.CLAUDE_CODE_PLUGIN_DIRS` 가 저장소 경로를 직접 가리킵니다 (tmux 로 바로 띄운 세션처럼 zshrc 를 거치지 않는 세션에도 적용).
>
> `alfred/workflows/*/` 는 Makefile 의 `ALFRED_WORKFLOWS` 와일드카드가 자동 발견합니다. Alfred 환경설정 폴더가 없으면 (미설치) 건너뛰고, 새로 만든 링크는 Alfred 가 켜져 있을 때 `reload workflow` 로 즉시 등록합니다.

## Git 설정과 호스트 로컬 설정

`git/gitconfig` 는 `[include] path = ~/.gitconfig_local` 을 가지고 있습니다. 호스트별 `user.email`, `includeIf` 등은 `~/.gitconfig_local` (저장소 외부) 에 두면 자동 로드됩니다.

기존 `~/.gitconfig` 가 실파일인 채로 `make sync` 를 실행하면 안전장치가 발동해 마이그레이션 안내 후 중단합니다:

```bash
mv ~/.gitconfig ~/.gitconfig_local
make sync
```

## .claude 디렉토리 구조 (프로젝트 로컬)

```
.claude/
├── plan/                   # 작업 계획서 (claude/settings.json 의 plansDirectory, 계획 모드에서 자동 생성)
├── skills/                 # 프로젝트 로컬 skill (setup-env, dotfiles-doctor)
├── settings.json           # 프로젝트 훅 (세션 시작 시 dotfiles-doctor 실행 제안)
└── settings.local.json     # 프로젝트 로컬 설정
```
