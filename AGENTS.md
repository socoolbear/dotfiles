# AGENTS.md

> AI 에이전트가 이 저장소를 이해하고 작업하기 위한 가이드
> 코딩 스타일은 `rules/coding-style.md` 참조, 워크플로우/언어/환경은 `~/.claude/AGENTS.md` 참조

## 프로젝트 개요

macOS 개발 환경을 위한 개인 dotfiles 저장소. Makefile 기반 심볼릭 링크 관리를 통해 설정 파일들을 관리합니다.

## 프로젝트 구조

| 디렉토리 | 설명 | 대상 경로 |
|----------|------|-----------|
| `zsh/` | Zsh 설정 (Oh My Zsh) | `~/.zshrc` |
| `vim/` | Vim/GVim 설정 | `~/.vimrc`, `~/.gvimrc` |
| `tmux/` | Tmux 설정 (oh-my-tmux) | `~/.config/tmux/` |
| `git/` | Git 전역 설정 | 수동 설정 |
| `kitty/` | Kitty 터미널 설정 | `~/.config/kitty/` |
| `ghostty/` | Ghostty 터미널 설정 | `~/.config/ghostty/` |
| `lvim/` | LunarVim 설정 | `~/.config/lvim/` |
| `karabiner/` | 키보드 리맵핑 | `~/.config/karabiner/` |
| `idea/` | IdeaVim (JetBrains IDE) | `~/.ideavimrc` |
| `claude/` | Claude Code 글로벌 설정 | `~/.claude/` |
| `nvm/` | NVM 기본 패키지 | `~/.nvm/default-packages` |
| `opencode/` | OpenCode 설정 | `~/.config/opencode/` |
| `.claude/` | 프로젝트 로컬 Claude 설정 | 로컬 전용 |

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
| `claude/.mcp.json` | `~/.mcp.json` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/AGENTS.md` | `~/.claude/AGENTS.md` |
| `claude/commands/*.md` | `~/.claude/commands/*.md` |
| `nvm/default-packages` | `~/.nvm/default-packages` |
| `opencode/oh-my-opencode.json` | `~/.config/opencode/oh-my-opencode.json` |

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
- [ ] `make sync` 가 정상 동작하는가?
- [ ] 기존 심볼릭 링크가 영향받지 않았는가?
