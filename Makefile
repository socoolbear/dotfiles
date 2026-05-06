.PHONY: all clean sync ohmyzsh ohmytmux backup brew brew-core brew-apps \
        mise npm macos bootstrap fresh update help

# Makefile 위치 기반 (cwd 와 독립) — make -C / -f 에서도 안전
DOTFILES := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))

all: sync

#--------------------------------------------------------------------------
# 도움말
#--------------------------------------------------------------------------

help:
	@echo "Make 명령어:"
	@echo ""
	@echo "  [새 장비]"
	@echo "    bootstrap     Xcode CLT + Homebrew + clone + fresh (one-shot)"
	@echo "    fresh         brew + sync + mise + npm + macos"
	@echo ""
	@echo "  [일상 동기화]"
	@echo "    update        brew + sync"
	@echo "    sync          심볼릭 링크 생성 (oh-my-zsh, oh-my-tmux 자동 설치)"
	@echo "    brew          Brewfile 적용 (코어 CLI 도구)"
	@echo "    brew-apps     Brewfile.apps 적용 (GUI 앱 + Mac App Store)"
	@echo "    mise          mise/config.toml 의 글로벌 도구 설치 (node, go)"
	@echo "    npm           NPM globals (npm/globals.txt + @nestjs/cli)"
	@echo "    macos         macOS 시스템 기본값 (macos/defaults.sh)"
	@echo ""
	@echo "  [관리]"
	@echo "    backup        호스트 로컬 데이터 백업 (~/backup_dotfiles/)"
	@echo "    clean         심볼릭 링크 제거"
	@echo "    help          본 도움말"

#--------------------------------------------------------------------------
# Homebrew 패키지 (Brewfile / Brewfile.apps)
#--------------------------------------------------------------------------

brew: brew-core

brew-core:
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew 가 필요합니다. https://brew.sh"; exit 1; }
	brew bundle install --file=$(DOTFILES)/Brewfile

brew-apps:
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew 가 필요합니다. https://brew.sh"; exit 1; }
	brew bundle install --file=$(DOTFILES)/Brewfile.apps

#--------------------------------------------------------------------------
# 심볼릭 링크 매니페스트 (sync / clean 공유)
# 형식: <source-relative-to-DOTFILES>:<target-relative-to-HOME>
#--------------------------------------------------------------------------

# 단일 파일 — 기존 심링크가 있으면 유지 (멱등)
LINKS_SINGLE := \
    zsh/zshrc:.zshrc \
    vim/vimrc:.vimrc \
    vim/gvimrc:.gvimrc \
    idea/ideavimrc:.ideavimrc \
    git/gitconfig:.gitconfig \
    git/gitignore_global:.gitignore_global \
    tmux/tmux.conf.local:.config/tmux/tmux.conf.local \
    claude/settings.json:.claude/settings.json \
    claude/CLAUDE.md:.claude/CLAUDE.md \
    claude/AGENTS.md:.claude/AGENTS.md \
    claude/.mcp.json:.mcp.json \
    mise/config.toml:.config/mise/config.toml \
    opencode/oh-my-opencode.json:.config/opencode/oh-my-opencode.json

# 디렉토리 — rm -rf 후 재링크 (내부 파일 변경을 즉시 반영)
LINKS_DIR := \
    kitty:.config/kitty \
    ghostty:.config/ghostty \
    lvim:.config/lvim \
    karabiner:.config/karabiner \
    claude/rules:.claude/rules \
    claude/scripts:.claude/scripts \
    claude/docs:.claude/docs

# claude/commands/*.md — 와일드카드 자동 발견 (파일 추가 시 Makefile 수정 불필요)
COMMANDS := $(notdir $(wildcard $(DOTFILES)/claude/commands/*.md))

# claude/skills/*/ — 와일드카드 자동 발견 (skill 추가 시 Makefile 수정 불필요)
# 디렉토리 단위 심링크 + [ -L ] 체크로 머신별 실디렉토리 (예: commit-and-push) 보존
SKILLS := $(notdir $(wildcard $(DOTFILES)/claude/skills/*))

#--------------------------------------------------------------------------
# 프레임워크 (oh-my-zsh / oh-my-tmux)
#--------------------------------------------------------------------------

ohmyzsh:
	@if [ ! -d "$(HOME)/.oh-my-zsh" ]; then \
		KEEP_ZSHRC=yes sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; \
		git clone https://github.com/zsh-users/zsh-autosuggestions "$(HOME)/.oh-my-zsh/custom/plugins/zsh-autosuggestions"; \
		git clone https://github.com/zsh-users/zsh-syntax-highlighting "$(HOME)/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"; \
	fi

ohmytmux:
	@mkdir -p $(HOME)/.config/tmux
	@if [ ! -d "$(HOME)/.config/tmux/.tmux" ]; then \
		git clone --single-branch https://github.com/gpakosz/.tmux.git $(HOME)/.config/tmux/.tmux; \
	fi
	@[ -L $(HOME)/.config/tmux/tmux.conf ] || ln -sf $(HOME)/.config/tmux/.tmux/.tmux.conf $(HOME)/.config/tmux/tmux.conf

#--------------------------------------------------------------------------
# sync — 심볼릭 링크 생성
#--------------------------------------------------------------------------

sync: ohmyzsh ohmytmux
	@# 안전장치: 기존 실파일이 있으면 마이그레이션 안내 후 중단
	@if [ -e $(HOME)/.gitconfig ] && [ ! -L $(HOME)/.gitconfig ]; then \
		echo "ERROR: ~/.gitconfig 가 실파일입니다."; \
		echo "  마이그레이션: mv ~/.gitconfig ~/.gitconfig_local && make sync"; \
		echo "  (dotfiles 의 git/gitconfig 가 [include] 로 ~/.gitconfig_local 을 자동 로드합니다)"; \
		exit 1; \
	fi
	@if [ -e $(HOME)/.gitignore_global ] && [ ! -L $(HOME)/.gitignore_global ]; then \
		echo "ERROR: ~/.gitignore_global 가 실파일입니다."; \
		echo "  마이그레이션: mv ~/.gitignore_global ~/.gitignore_global.bak && make sync"; \
		exit 1; \
	fi

	@# 디렉토리 생성
	@mkdir -p $(HOME)/.local/bin $(HOME)/.config $(HOME)/.config/mise \
	          $(HOME)/.claude $(HOME)/.claude/commands $(HOME)/.claude/skills $(HOME)/.config/opencode

	@# 단일 파일 심링크
	@for entry in $(LINKS_SINGLE); do \
	    src=$${entry%%:*}; dst=$${entry##*:}; \
	    target="$(HOME)/$$dst"; \
	    mkdir -p "$$(dirname "$$target")"; \
	    [ -L "$$target" ] || ln -sf "$(DOTFILES)/$$src" "$$target"; \
	done

	@# tmux.conf 잔재 정리 (oh-my-tmux 가 ~/.config/tmux/tmux.conf 사용)
	@rm -f $(HOME)/.tmux.conf

	@# claude/commands/*.md 자동 발견 후 심링크
	@for cmd in $(COMMANDS); do \
	    target="$(HOME)/.claude/commands/$$cmd"; \
	    [ -L "$$target" ] || ln -sf "$(DOTFILES)/claude/commands/$$cmd" "$$target"; \
	done

	@# claude/skills/* 자동 발견 후 심링크 ([ -L ] 체크로 머신별 실디렉토리 보존)
	@for skill in $(SKILLS); do \
	    target="$(HOME)/.claude/skills/$$skill"; \
	    [ -L "$$target" ] || ln -sf "$(DOTFILES)/claude/skills/$$skill" "$$target"; \
	done

	@# 디렉토리 심링크 (rm -rf 후 재링크)
	@for entry in $(LINKS_DIR); do \
	    src=$${entry%%:*}; dst=$${entry##*:}; \
	    target="$(HOME)/$$dst"; \
	    mkdir -p "$$(dirname "$$target")"; \
	    rm -rf "$$target"; \
	    ln -sf "$(DOTFILES)/$$src" "$$target"; \
	done

#--------------------------------------------------------------------------
# clean — 심볼릭 링크 제거
#--------------------------------------------------------------------------

clean:
	@for entry in $(LINKS_SINGLE); do \
	    rm -f "$(HOME)/$${entry##*:}"; \
	done
	@for entry in $(LINKS_DIR); do \
	    rm -rf "$(HOME)/$${entry##*:}"; \
	done
	@for cmd in $(COMMANDS); do \
	    rm -f "$(HOME)/.claude/commands/$$cmd"; \
	done
	@for skill in $(SKILLS); do \
	    rm -f "$(HOME)/.claude/skills/$$skill"; \
	done
	@# tmux 부속 정리
	@rm -rf $(HOME)/.config/tmux/.tmux
	@rm -f $(HOME)/.config/tmux/tmux.conf
	@rm -f $(HOME)/.tmux.conf

#--------------------------------------------------------------------------
# backup — 기존 dotfiles 백업 (~/backup_dotfiles/)
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
# mise — 글로벌 도구 매니저 (Node/Go 통합)
#--------------------------------------------------------------------------

mise:
	@command -v mise >/dev/null 2>&1 || { echo "mise 가 필요합니다. 'make brew' 먼저 실행."; exit 1; }
	mise install

#--------------------------------------------------------------------------
# NPM globals (npm/globals.txt 매니페스트 + 추가 도구)
#--------------------------------------------------------------------------

npm:
	@command -v mise >/dev/null 2>&1 || { echo "mise 가 필요합니다. 'make mise' 먼저 실행."; exit 1; }
	@mise exec node -- bash -c 'xargs -L1 npm install -g' < $(DOTFILES)/npm/globals.txt
	@mise exec node -- npm install -g @nestjs/cli

#--------------------------------------------------------------------------
# macOS defaults
#--------------------------------------------------------------------------

macos:
	@bash $(DOTFILES)/macos/defaults.sh

#--------------------------------------------------------------------------
# 종합 타겟
#--------------------------------------------------------------------------

# 새 장비 1-shot 셋업 (bootstrap.sh 와 등가)
bootstrap:
	@bash $(DOTFILES)/bootstrap.sh

# 새 장비용: 모든 자동화 단계 일괄 실행
fresh: brew sync mise npm macos
	@echo "==> fresh 셋업 완료. 추가 안내는 bootstrap.sh 출력 참고."

# 일상 동기화: brew + sync 만
update: brew sync

#--------------------------------------------------------------------------
# backup — 기존 dotfiles 백업
#--------------------------------------------------------------------------

backup:
	mkdir -p $(HOME)/backup_dotfiles
	# 호스트 로컬 / 시크릿 (가장 중요 — 잃으면 재생성 어려움)
	-cp -i $(HOME)/.gitconfig_local $(HOME)/backup_dotfiles/gitconfig_local
	-cp -i $(HOME)/.private-exports $(HOME)/backup_dotfiles/private-exports
	# dotfiles 심링크의 실제 내용 (참고용 — 원본은 repo)
	-cp -L -i $(HOME)/.zshrc $(HOME)/backup_dotfiles/zshrc
	-cp -L -i $(HOME)/.vimrc $(HOME)/backup_dotfiles/vimrc
	-cp -L -i $(HOME)/.gvimrc $(HOME)/backup_dotfiles/gvimrc
	-cp -L -i $(HOME)/.ideavimrc $(HOME)/backup_dotfiles/ideavimrc
	-cp -L -i $(HOME)/.gitconfig $(HOME)/backup_dotfiles/gitconfig
	-cp -L -i $(HOME)/.gitignore_global $(HOME)/backup_dotfiles/gitignore_global
	-cp -L -i $(HOME)/.config/tmux/tmux.conf.local $(HOME)/backup_dotfiles/tmux.conf.local
	-cp -L -i $(HOME)/.config/mise/config.toml $(HOME)/backup_dotfiles/mise-config.toml
	# 디렉토리 (실파일 또는 심링크 모두 처리)
	-cp -RL $(HOME)/.config/karabiner $(HOME)/backup_dotfiles/karabiner 2>/dev/null
	-cp -RL $(HOME)/.config/kitty $(HOME)/backup_dotfiles/kitty 2>/dev/null
	-cp -RL $(HOME)/.config/lvim $(HOME)/backup_dotfiles/lvim 2>/dev/null
	@echo "==> 백업 완료: $(HOME)/backup_dotfiles/"
	@echo "==> 가장 중요한 파일: gitconfig_local, private-exports (repo 외부 데이터)"
