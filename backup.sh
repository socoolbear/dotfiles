#!/usr/bin/env bash

BACKUP_DOTFILES=$HOME/backup_dotfiles

mkdir -p "$BACKUP_DOTFILES"

cp -i "$HOME"/.zshrc "$BACKUP_DOTFILES"/zshrc
cp -i "$HOME"/.vimrc "$BACKUP_DOTFILES"/vimrc
cp -i "$HOME"/.ideavimrc "$BACKUP_DOTFILES"/ideavimrc
cp -i "$HOME"/.tmuxconf "$BACKUP_DOTFILES"/tmuxconf
