# 프로젝트 구조 및 심볼릭 링크 매핑

## 디렉토리 개요

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
| `mise/` | mise 글로벌 도구 매니페스트 (node, go 등) | `~/.config/mise/config.toml` | ✅ |
| `npm/` | 글로벌 NPM 패키지 매니페스트 (`make npm` 이 사용) | — | ❌ (repo 내부 참조) |
| `opencode/` | OpenCode 설정 | `~/.config/opencode/` | ✅ |
| `git/` | Git 설정 (alias / delta / include) | `~/.gitconfig`, `~/.gitignore_global` | ✅ |
| `copilot/` | GitHub Copilot 인스트럭션 템플릿 | 프로젝트별 `.github/` | ❌ (수동 복사) |
| `.claude/` | 프로젝트 로컬 Claude 설정 | 로컬 전용 | — |

## 심볼릭 링크 매핑 — 단일 파일

| Source | Target |
|--------|--------|
| `zsh/zshrc` | `~/.zshrc` |
| `vim/vimrc` | `~/.vimrc` |
| `vim/gvimrc` | `~/.gvimrc` |
| `idea/ideavimrc` | `~/.ideavimrc` |
| `git/gitconfig` | `~/.gitconfig` |
| `git/gitignore_global` | `~/.gitignore_global` |
| `tmux/tmux.conf.local` | `~/.config/tmux/tmux.conf.local` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/AGENTS.md` | `~/.claude/AGENTS.md` |
| `claude/.mcp.json` | `~/.mcp.json` *(주의: `~/.claude/` 가 아닌 홈 루트)* |
| `claude/commands/*.md` | `~/.claude/commands/<name>.md` *(와일드카드 자동 발견)* |
| `claude/skills/*/` | `~/.claude/skills/<name>/` *(와일드카드 자동 발견, 디렉토리 단위)* |
| `mise/config.toml` | `~/.config/mise/config.toml` |
| `opencode/oh-my-opencode.json` | `~/.config/opencode/oh-my-opencode.json` |

> `claude/commands/*.md` 와 `claude/skills/*/` 는 Makefile 의 `COMMANDS` / `SKILLS` 와일드카드가 자동 발견하므로, 새 명령/skill 을 추가해도 Makefile 수정 불필요.
> 단, skills 는 `[ -L ]` 체크로 심링크만 만들고 머신별 실디렉토리 (예: dotfiles 에 없는 로컬 skill) 는 보존합니다.

## 심볼릭 링크 매핑 — 디렉토리

| Source | Target |
|--------|--------|
| `kitty/` | `~/.config/kitty/` |
| `ghostty/` | `~/.config/ghostty/` |
| `lvim/` | `~/.config/lvim/` |
| `karabiner/` | `~/.config/karabiner/` |
| `claude/rules/` | `~/.claude/rules/` |
| `claude/scripts/` | `~/.claude/scripts/` |
| `claude/docs/` | `~/.claude/docs/` |

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
├── plans/                  # 작업 계획서 (계획 모드에서 자동 생성)
├── rules/
│   └── coding-style.md     # 코딩 스타일 규칙 (자동 로드)
└── settings.local.json     # 프로젝트 로컬 설정
```
