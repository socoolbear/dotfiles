#!/usr/bin/env bash

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME"/.local/bin

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ln -sf "$DOTFILES"/zsh/zshrc "$HOME"/.zshrc
ln -sf "$DOTFILES"/vim/vimrc "$HOME"/.vimrc
ln -sf "$DOTFILES"/idea/ideavimrc "$HOME"/.ideavimrc
#ln -sf "$DOTFILES"/tmux/tmux.conf "$HOME"/.tmux.conf
#
#ln -sf "$DOTFILES"/scripts/t "$HOME"/.local/bin/t
#
#rm -rf "$HOME"/.config/kitty
#ln -s "$DOTFILES"/kitty "$HOME"/.config/kitty
#
#ln -sf "$DOTFILES"/git/gitconfig "$HOME"/.gitconfig
#
#ln -sf "$DOTFILES"/git/gitignore_global "$HOME"/.gitignore_global
#
#rm -rf "$HOME"/.config/phpactor
#ln -s "$DOTFILES"/phpactor "$HOME"/.config/phpactor
#
#mkdir -p "$HOME"/.nvm
#ln -sf "$DOTFILES"/nvm/default-packages "$HOME"/.nvm/default-packages
#
#rm -rf "$HOME"/.config/nvim
#ln -s "$DOTFILES"/nvim "$HOME"/.config/nvim

