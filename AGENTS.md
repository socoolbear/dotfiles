# AGENTS.md

> AI 에이전트가 이 저장소를 이해하고 작업하기 위한 가이드
> 코딩 스타일은 `claude/rules/coding-style.md`, 워크플로우/언어/환경은 `~/.claude/AGENTS.md` 참조

## 프로젝트 개요

macOS 개발 환경을 위한 개인 dotfiles 저장소. Makefile 기반 심볼릭 링크 관리를 통해 설정 파일들을 한 곳에서 관리합니다.

## 프로젝트 구조

| 디렉토리 | 설명 | 대상 경로 | 자동 링크 |
|----------|------|-----------|-----------|
| `zsh/` | Zsh 설정 (oh-my-zsh) | `~/.zshrc` | ✅ |
| `vim/` | Vim/GVim 설정 | `~/.vimrc`, `~/.gvimrc` | ✅ |
| `idea/` | IdeaVim (JetBrains IDE) | `~/.ideavimrc` | ✅ |
| `tmux/` | Tmux 설정 (oh-my-tmux) | `~/.config/tmux/` | ✅ |
| `kitty/` | Kitty 터미널 | `~/.config/kitty/` | ✅ |
| `ghostty/` | Ghostty 터미널 | `~/.config/ghostty/` | ✅ |
| `lvim/` | LunarVim | `~/.config/lvim/` | ✅ |
| `karabiner/` | 키보드 리맵핑 | `~/.config/karabiner/` | ✅ |
| `claude/` | Claude Code 글로벌 설정 | `~/.claude/`, `~/.mcp.json` | ✅ (부분) |
| `nvm/` | NVM 기본 패키지 | `~/.nvm/default-packages` | ✅ |
| `opencode/` | OpenCode 설정 | `~/.config/opencode/` | ✅ |
| `git/` | Git 설정 템플릿 | — | ❌ (수동 복사) |
| `copilot/` | GitHub Copilot 인스트럭션 템플릿 | 프로젝트별 `.github/` | ❌ (수동 복사) |
| `.claude/` | 프로젝트 로컬 Claude 설정 | 로컬 전용 | — |

## 명령어

```bash
make sync     # 설치 (심볼릭 링크 생성, oh-my-zsh, oh-my-tmux 자동 설치)
make clean    # 심볼릭 링크 제거
make backup   # 기존 dotfiles 백업 (~/backup_dotfiles/)
```

## 심볼릭 링크 매핑

### 단일 파일

| Source | Target |
|--------|--------|
| `zsh/zshrc` | `~/.zshrc` |
| `vim/vimrc` | `~/.vimrc` |
| `vim/gvimrc` | `~/.gvimrc` |
| `idea/ideavimrc` | `~/.ideavimrc` |
| `tmux/tmux.conf.local` | `~/.config/tmux/tmux.conf.local` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/AGENTS.md` | `~/.claude/AGENTS.md` |
| `claude/.mcp.json` | `~/.mcp.json` *(주의: `~/.claude/` 가 아닌 홈 루트)* |
| `claude/commands/handoff.md` | `~/.claude/commands/handoff.md` |
| `claude/commands/scaffold-claude.md` | `~/.claude/commands/scaffold-claude.md` |
| `nvm/default-packages` | `~/.nvm/default-packages` |
| `opencode/oh-my-opencode.json` | `~/.config/opencode/oh-my-opencode.json` |

> `claude/commands/` 에 새 명령을 추가할 때마다 Makefile 의 `sync` / `clean` 양쪽에 줄을 추가해야 합니다.

### 디렉토리

| Source | Target |
|--------|--------|
| `kitty/` | `~/.config/kitty/` |
| `ghostty/` | `~/.config/ghostty/` |
| `lvim/` | `~/.config/lvim/` |
| `karabiner/` | `~/.config/karabiner/` |
| `claude/rules/` | `~/.claude/rules/` |
| `claude/scripts/` | `~/.claude/scripts/` |

## 아키텍처

### Makefile 기반 관리

- **단일 파일**: `[ -L ... ] || ln -sf` 패턴으로 멱등 심볼릭 링크
- **디렉토리**: `rm -rf` 후 `ln -sf` 패턴으로 전체 교체
- **프레임워크**: oh-my-zsh, oh-my-tmux 자동 설치

### oh-my-tmux 주의사항

- `tmux.conf` 는 oh-my-tmux 가 관리 (수정 금지)
- `tmux.conf.local` 만 커스터마이징
- 위치: `~/.config/tmux/` (XDG 표준)

### claude/ 하위 구성

- `claude/settings.json` — Claude Code 글로벌 설정 (hooks, 권한, 환경변수)
- `claude/.mcp.json` — MCP 서버 정의 (홈 루트 `~/.mcp.json` 으로 링크)
- `claude/CLAUDE.md` / `claude/AGENTS.md` — 글로벌 인스트럭션
- `claude/rules/` — 자동 로드되는 규칙 모음 (예: `coding-style.md`)
- `claude/scripts/` — Hook 등에서 호출하는 유틸 스크립트 (예: `notify.sh`, `statusline-command.sh`)
- `claude/commands/` — 슬래시 명령어 정의

### `make backup` 의 한계

`make backup` 은 zsh, vim, idea, tmux, git, kitty, lvim, karabiner, nvm 만 백업합니다. 다음은 백업 대상이 아니므로 필요시 직접 처리:
- `~/.config/ghostty/`
- `~/.config/opencode/`
- `~/.claude/` (settings.json 등)
- `~/.mcp.json`

## .claude 디렉토리 구조

```
.claude/
├── plans/                  # 작업 계획서 (계획 모드에서 자동 생성)
├── rules/
│   └── coding-style.md     # 코딩 스타일 규칙 (자동 로드)
└── settings.local.json     # 프로젝트 로컬 설정
```

## 작업 완료 체크리스트

- [ ] 요청된 모든 변경사항이 반영되었는가?
- [ ] `make sync` 가 정상 동작하는가? (멱등성 확인)
- [ ] 새로운 심볼릭 링크 추가 시 `make clean` 에도 대응 줄을 추가했는가?
- [ ] 기존 심볼릭 링크가 영향받지 않았는가?
