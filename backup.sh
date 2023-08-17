#!/usr/bin/env bash

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DOTFILES=$HOME/backup_dotfiles

cp -f "$DOTFILES"/zsh/.zshrc "$BACKUP_DOTFILES"/