#!/usr/bin/env bash

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME"/.local/bin

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ln -sf "$DOTFILES"/zsh/zshrc "$HOME"/.zshrc
ln -sf "$DOTFILES"/vim/vimrc "$HOME"/.vimrc
ln -sf "$DOTFILES"/idea/ideavimrc "$HOME"/.ideavimrc
ln -sf "$DOTFILES"/tmux/tmux.conf "$HOME"/.tmux.conf

rm -rf "$HOME"/.config/kitty
ln -sf "$DOTFILES"/kitty "$HOME"/.config/kitty

rm -rf "$HOME"/.config/lvim
ln -sf "$DOTFILES"/lvim "$HOME"/.config/lvim

#ln -sf "$DOTFILES"/git/gitconfig "$HOME"/.gitconfig
#ln -sf "$DOTFILES"/git/gitignore_global "$HOME"/.gitignore_global

ln -sf "$DOTFILES"/karabiner "$HOME"/.config/karabiner

mkdir -p "$HOME"/.nvm
ln -sf "$DOTFILES"/nvm/default-packages "$HOME"/.nvm/default-packages