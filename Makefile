.PHONY: all clean sync ohmyzsh backup

DOTFILES := $(shell pwd)

all: sync

ohmyzsh:
	@if [ ! -d "$(HOME)/.oh-my-zsh" ]; then \
		KEEP_ZSHRC=yes sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; \
		git clone https://github.com/zsh-users/zsh-autosuggestions "$(HOME)/.oh-my-zsh/custom/plugins/zsh-autosuggestions"; \
		git clone https://github.com/zsh-users/zsh-syntax-highlighting "$(HOME)/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"; \
	fi

sync: ohmyzsh
	# 디렉토리 생성
	mkdir -p $(HOME)/.local/bin
	mkdir -p $(HOME)/.config
	mkdir -p $(HOME)/.nvm
	mkdir -p $(HOME)/.claude
	mkdir -p $(HOME)/.claude/commands
	mkdir -p $(HOME)/.claude/scripts

	# 단일 파일 심볼릭 링크
	[ -L $(HOME)/.zshrc ] || ln -sf $(DOTFILES)/zsh/zshrc $(HOME)/.zshrc
	[ -L $(HOME)/.vimrc ] || ln -sf $(DOTFILES)/vim/vimrc $(HOME)/.vimrc
	[ -L $(HOME)/.gvimrc ] || ln -sf $(DOTFILES)/vim/gvimrc $(HOME)/.gvimrc
	[ -L $(HOME)/.ideavimrc ] || ln -sf $(DOTFILES)/idea/ideavimrc $(HOME)/.ideavimrc
	[ -L $(HOME)/.tmux.conf ] || ln -sf $(DOTFILES)/tmux/tmux.conf $(HOME)/.tmux.conf
	[ -L $(HOME)/.claude/settings.json ] || ln -sf $(DOTFILES)/claude/settings.json $(HOME)/.claude/settings.json
	[ -L $(HOME)/.nvm/default-packages ] || ln -sf $(DOTFILES)/nvm/default-packages $(HOME)/.nvm/default-packages
	[ -L $(HOME)/.claude/commands/handoff.md ] || ln -sf $(DOTFILES)/claude/commands/handoff.md $(HOME)/.claude/commands/handoff.md
	[ -L $(HOME)/.claude/scripts/statusline.sh ] || ln -sf $(DOTFILES)/claude/scripts/statusline.sh $(HOME)/.claude/scripts/statusline.sh

	# 디렉토리 심볼릭 링크 (기존 제거 후 링크)
	rm -rf $(HOME)/.config/kitty
	ln -sf $(DOTFILES)/kitty $(HOME)/.config/kitty

	rm -rf $(HOME)/.config/lvim
	ln -sf $(DOTFILES)/lvim $(HOME)/.config/lvim

	rm -rf $(HOME)/.config/karabiner
	ln -sf $(DOTFILES)/karabiner $(HOME)/.config/karabiner

clean:
	rm -f $(HOME)/.zshrc
	rm -f $(HOME)/.vimrc
	rm -f $(HOME)/.gvimrc
	rm -f $(HOME)/.ideavimrc
	rm -f $(HOME)/.tmux.conf
	rm -f $(HOME)/.claude/settings.json
	rm -f $(HOME)/.claude/commands/handoff.md
	rm -f $(HOME)/.claude/scripts/statusline.sh
	rm -f $(HOME)/.nvm/default-packages
	rm -rf $(HOME)/.config/kitty
	rm -rf $(HOME)/.config/lvim
	rm -rf $(HOME)/.config/karabiner

backup:
	mkdir -p $(HOME)/backup_dotfiles
	-cp -i $(HOME)/.zshrc $(HOME)/backup_dotfiles/zshrc
	-cp -i $(HOME)/.vimrc $(HOME)/backup_dotfiles/vimrc
	-cp -i $(HOME)/.gvimrc $(HOME)/backup_dotfiles/gvimrc
	-cp -i $(HOME)/.ideavimrc $(HOME)/backup_dotfiles/ideavimrc
	-cp -i $(HOME)/.tmux.conf $(HOME)/backup_dotfiles/tmuxconf
	-cp -i $(HOME)/.gitconfig $(HOME)/backup_dotfiles/gitconfig
	-cp -i $(HOME)/.gitignore_global $(HOME)/backup_dotfiles/gitignore_global
	-cp -ir $(HOME)/.config/karabiner $(HOME)/backup_dotfiles/karabiner
	-cp -ir $(HOME)/.config/kitty $(HOME)/backup_dotfiles/kitty
	-cp -ir $(HOME)/.config/lvim $(HOME)/backup_dotfiles/lvim
	-cp -ir $(HOME)/.nvm/default-packages $(HOME)/backup_dotfiles/nvm-default-packages
