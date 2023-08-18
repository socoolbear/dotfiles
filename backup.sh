#!/usr/bin/env bash

BACKUP_DOTFILES=$HOME/backup_dotfiles

mkdir -p "$BACKUP_DOTFILES"
cp -f "$HOME"/.zshrc "$BACKUP_DOTFILES"/zshrc