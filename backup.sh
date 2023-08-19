#!/usr/bin/env bash

BACKUP_DOTFILES=$HOME/backup_dotfiles

mkdir -p "$BACKUP_DOTFILES"

cp -i "$HOME"/.zshrc "$BACKUP_DOTFILES"/zshrc
cp -i "$HOME"/.vimrc "$BACKUP_DOTFILES"/vimrc
cp -i "$HOME"/.ideavimrc "$BACKUP_DOTFILES"/ideavimrc
cp -i "$HOME"/.tmux.conf "$BACKUP_DOTFILES"/tmuxconf
cp -ir "$HOME"/.config/kitty "$BACKUP_DOTFILES"/kitty
cp -ir "$HOME"/.config/lvim "$BACKUP_DOTFILES"/lvim
