# AGENTS.md

> AI 에이전트가 이 저장소를 이해하고 작업하기 위한 상세 가이드

## 프로젝트 개요

macOS 개발 환경을 위한 개인 dotfiles 저장소입니다. Makefile 기반 심볼릭 링크 관리를 통해 zsh, vim, tmux, git, kitty, ghostty, LunarVim, Karabiner-Elements, IdeaVim, Claude Code, NVM 설정을 관리합니다.

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
| `claude/` | Claude Code 설정 | `~/.claude/` |
| `nvm/` | NVM 기본 패키지 | `~/.nvm/default-packages` |
| `.claude/` | 프로젝트 로컬 Claude 설정 | 로컬 전용 |

## 명령어

```bash
# 설치 (심볼릭 링크 생성, oh-my-zsh, oh-my-tmux 자동 설치)
make sync

# 심볼릭 링크 제거
make clean

# 기존 dotfiles 백업 (~/backup_dotfiles/)
make backup
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
| `claude/commands/handoff.md` | `~/.claude/commands/handoff.md` |
| `claude/scripts/notify.sh` | `~/.claude/scripts/notify.sh` |
| `claude/scripts/notify-stop.sh` | `~/.claude/scripts/notify-stop.sh` |
| `nvm/default-packages` | `~/.nvm/default-packages` |

### 디렉토리

| Source | Target |
|--------|--------|
| `kitty/` | `~/.config/kitty/` |
| `ghostty/` | `~/.config/ghostty/` |
| `lvim/` | `~/.config/lvim/` |
| `karabiner/` | `~/.config/karabiner/` |
| `claude/rules/` | `~/.claude/rules/` |

## 아키텍처

### Makefile 기반 관리

- **단일 파일**: 홈 디렉토리에 직접 심볼릭 링크
- **디렉토리**: `~/.config/` 하위에 심볼릭 링크
- **프레임워크**: oh-my-zsh, oh-my-tmux 자동 설치

### oh-my-tmux 사용법

tmux 설정은 [gpakosz/.tmux](https://github.com/gpakosz/.tmux) (oh-my-tmux) 프레임워크를 사용합니다.

- `tmux.conf` 는 oh-my-tmux 가 관리 (수정 금지)
- `tmux.conf.local` 만 커스터마이징
- 위치: `~/.config/tmux/` (XDG 표준)

## .claude 디렉토리 구조

```
.claude/
├── plans/                  # 작업 계획서 저장소
├── rules/                  # 코딩 규칙
│   ├── coding-style.md     # 코딩 스타일 가이드
│   └── agents.md           # 에이전트 오케스트레이션 규칙
└── settings.local.json     # 프로젝트 로컬 설정
```

### rules/ 디렉토리

프로젝트별 코딩 규칙을 정의합니다. Claude Code 가 자동으로 읽어 적용합니다.

### plans/ 디렉토리

작업 계획서를 저장합니다. 계획 모드에서 생성된 계획이 이 디렉토리에 저장됩니다.

## 코딩 스타일 가이드라인

### 일반 원칙

- **Early return**: 중첩 조건문 대신 조기 반환 사용
- **빈 줄**: 변수 선언과 제어문/함수 호출 사이에 빈 줄 추가
- **Immutability**: 가변 객체/클래스 사용 지양
- **Single responsibility**: 함수는 단일 책임 원칙 준수

### 네이밍

- **함수명**: 동사 사용 (예: `createSymlink`, `backupFile`)
- **변수명**: 명사 사용 (예: `dotfilesPath`, `targetDir`)

### TypeScript 특정

- Nullish coalescing 연산자 `??` 사용 (`||` 대신)

## AI 응답 가이드라인

### 언어

- **한국어**로 응답 (가능한 한)
- **Git 커밋 메시지**도 한국어로 작성
- 영어와 한국어 혼용 시 **띄어쓰기** (예: "Dockerfile 에서" O, "Dockerfile에서" X)

### 대상 환경

- **macOS** 사용자 대상
- Homebrew 등 macOS 패키지 관리자 사용 가정

### 작업 완료 체크리스트

작업 완료 시 다음 항목을 확인합니다:

- [ ] 요청된 모든 변경사항이 반영되었는가?
- [ ] `make sync` 가 정상 동작하는가?
- [ ] 기존 기능이 영향받지 않았는가?

## 관련 파일

- `CLAUDE.md`: 프로젝트 기본 지침 (간략)
- `AGENTS.md`: AI 에이전트 상세 가이드 (이 파일)
- `.claude/settings.local.json`: 프로젝트 로컬 설정
- `.claude/rules/`: 코딩 규칙
