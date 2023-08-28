#!/usr/bin/env bash

BACKUP_DOTFILES=$HOME/backup_dotfiles

mkdir -p "$BACKUP_DOTFILES"

cp -i "$HOME"/.zshrc "$BACKUP_DOTFILES"/zshrc
cp -i "$HOME"/.vimrc "$BACKUP_DOTFILES"/vimrc
cp -i "$HOME"/.ideavimrc "$BACKUP_DOTFILES"/ideavimrc
cp -i "$HOME"/.tmux.conf "$BACKUP_DOTFILES"/tmuxconf
cp -i "$HOME"/.gitconfig "$BACKUP_DOTFILES"/gitconfig
cp -i "$HOME"/.gitignore_global "$BACKUP_DOTFILES"/gitignore_global

cp -ir "$HOME"/.config/karabiner "$BACKUP_DOTFILES"/karabiner
cp -ir "$HOME"/.config/kitty "$BACKUP_DOTFILES"/kitty
cp -ir "$HOME"/.config/lvim "$BACKUP_DOTFILES"/lvim
cp -ir "$HOME"/.config/phpactor "$BACKUP_DOTFILES"/phpactor
cp -ir "$HOME"/.nvm/default-packages "$BACKUP_DOTFILES"/nvm-default-packages
