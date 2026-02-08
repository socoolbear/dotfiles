.PHONY: all clean sync ohmyzsh ohmytmux backup

DOTFILES := $(shell pwd)

all: sync

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

sync: ohmyzsh ohmytmux
	# 디렉토리 생성
	mkdir -p $(HOME)/.local/bin
	mkdir -p $(HOME)/.config
	mkdir -p $(HOME)/.nvm
	mkdir -p $(HOME)/.claude
	mkdir -p $(HOME)/.claude/commands

	# 단일 파일 심볼릭 링크
	[ -L $(HOME)/.zshrc ] || ln -sf $(DOTFILES)/zsh/zshrc $(HOME)/.zshrc
	[ -L $(HOME)/.vimrc ] || ln -sf $(DOTFILES)/vim/vimrc $(HOME)/.vimrc
	[ -L $(HOME)/.gvimrc ] || ln -sf $(DOTFILES)/vim/gvimrc $(HOME)/.gvimrc
	[ -L $(HOME)/.ideavimrc ] || ln -sf $(DOTFILES)/idea/ideavimrc $(HOME)/.ideavimrc
	# oh-my-tmux 사용 (XDG 경로: ~/.config/tmux)
	rm -f $(HOME)/.tmux.conf
	[ -L $(HOME)/.config/tmux/tmux.conf.local ] || ln -sf $(DOTFILES)/tmux/tmux.conf.local $(HOME)/.config/tmux/tmux.conf.local
	[ -L $(HOME)/.claude/settings.json ] || ln -sf $(DOTFILES)/claude/settings.json $(HOME)/.claude/settings.json
	[ -L $(HOME)/.claude/CLAUDE.md ] || ln -sf $(DOTFILES)/claude/CLAUDE.md $(HOME)/.claude/CLAUDE.md
	[ -L $(HOME)/.mcp.json ] || ln -sf $(DOTFILES)/claude/.mcp.json $(HOME)/.mcp.json
	[ -L $(HOME)/.nvm/default-packages ] || ln -sf $(DOTFILES)/nvm/default-packages $(HOME)/.nvm/default-packages
	[ -L $(HOME)/.claude/commands/handoff.md ] || ln -sf $(DOTFILES)/claude/commands/handoff.md $(HOME)/.claude/commands/handoff.md
	[ -L $(HOME)/.claude/commands/scaffold-claude.md ] || ln -sf $(DOTFILES)/claude/commands/scaffold-claude.md $(HOME)/.claude/commands/scaffold-claude.md

	# .claude 디렉토리 심볼릭 링크
	mkdir -p $(HOME)/.claude/rules
	rm -rf $(HOME)/.claude/rules
	ln -sf $(DOTFILES)/claude/rules $(HOME)/.claude/rules

	# 디렉토리 심볼릭 링크 (기존 제거 후 링크)
	rm -rf $(HOME)/.config/kitty
	ln -sf $(DOTFILES)/kitty $(HOME)/.config/kitty

	rm -rf $(HOME)/.config/ghostty
	ln -sf $(DOTFILES)/ghostty $(HOME)/.config/ghostty

	rm -rf $(HOME)/.config/lvim
	ln -sf $(DOTFILES)/lvim $(HOME)/.config/lvim

	rm -rf $(HOME)/.config/karabiner
	ln -sf $(DOTFILES)/karabiner $(HOME)/.config/karabiner

	# OpenCode 설정
	mkdir -p $(HOME)/.config/opencode
	[ -L $(HOME)/.config/opencode/oh-my-opencode.json ] || ln -sf $(DOTFILES)/opencode/oh-my-opencode.json $(HOME)/.config/opencode/oh-my-opencode.json

clean:
	rm -f $(HOME)/.zshrc
	rm -f $(HOME)/.vimrc
	rm -f $(HOME)/.gvimrc
	rm -f $(HOME)/.ideavimrc
	rm -f $(HOME)/.tmux.conf
	rm -f $(HOME)/.config/tmux/tmux.conf.local
	rm -rf $(HOME)/.config/tmux/.tmux
	rm -f $(HOME)/.config/tmux/tmux.conf
	rm -f $(HOME)/.claude/settings.json
	rm -f $(HOME)/.claude/CLAUDE.md
	rm -f $(HOME)/.mcp.json
	rm -f $(HOME)/.claude/commands/handoff.md
	rm -f $(HOME)/.claude/commands/scaffold-claude.md
	rm -rf $(HOME)/.claude/rules
	rm -f $(HOME)/.nvm/default-packages
	rm -rf $(HOME)/.config/kitty
	rm -rf $(HOME)/.config/lvim
	rm -rf $(HOME)/.config/karabiner
	rm -f $(HOME)/.config/opencode/oh-my-opencode.json

backup:
	mkdir -p $(HOME)/backup_dotfiles
	-cp -i $(HOME)/.zshrc $(HOME)/backup_dotfiles/zshrc
	-cp -i $(HOME)/.vimrc $(HOME)/backup_dotfiles/vimrc
	-cp -i $(HOME)/.gvimrc $(HOME)/backup_dotfiles/gvimrc
	-cp -i $(HOME)/.ideavimrc $(HOME)/backup_dotfiles/ideavimrc
	-cp -i $(HOME)/.config/tmux/tmux.conf.local $(HOME)/backup_dotfiles/tmux.conf.local
	-cp -i $(HOME)/.gitconfig $(HOME)/backup_dotfiles/gitconfig
	-cp -i $(HOME)/.gitignore_global $(HOME)/backup_dotfiles/gitignore_global
	-cp -ir $(HOME)/.config/karabiner $(HOME)/backup_dotfiles/karabiner
	-cp -ir $(HOME)/.config/kitty $(HOME)/backup_dotfiles/kitty
	-cp -ir $(HOME)/.config/lvim $(HOME)/backup_dotfiles/lvim
	-cp -ir $(HOME)/.nvm/default-packages $(HOME)/backup_dotfiles/nvm-default-packages
