# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles repository for macOS development environment. Manages configurations for zsh, vim, tmux, git, kitty, ghostty, LunarVim, Karabiner-Elements, IdeaVim, Claude Code, and NVM.

## Commands

```bash
# Install dotfiles (creates symlinks, installs oh-my-zsh and oh-my-tmux)
make sync

# Remove all symlinks
make clean

# Backup existing dotfiles to ~/backup_dotfiles/
make backup
```

## Architecture

**Symlink-based dotfile management** via Makefile:
- Single files (zshrc, vimrc, etc.) → symlinked to home directory
- Directories (kitty, lvim, karabiner, ghostty) → symlinked to ~/.config/
- oh-my-zsh and oh-my-tmux are auto-installed during `make sync`

**Key mappings:**
| Source | Target |
|--------|--------|
| zsh/zshrc | ~/.zshrc |
| vim/vimrc, vim/gvimrc | ~/.vimrc, ~/.gvimrc |
| idea/ideavimrc | ~/.ideavimrc |
| tmux/tmux.conf.local | ~/.config/tmux/tmux.conf.local |
| claude/settings.json | ~/.claude/settings.json |
| claude/scripts/*.sh | ~/.claude/scripts/ |
| nvm/default-packages | ~/.nvm/default-packages |

**Tmux uses oh-my-tmux framework** (gpakosz/.tmux) - edit `tmux/tmux.conf.local` for customizations, not tmux.conf directly.

## Language Guidelines

- Respond in Korean (가능한 한 한국어로 답변)
- Git commit messages in Korean
- When mixing English and Korean, add space between them (e.g., "Dockerfile 에서" not "Dockerfile에서")
- Target macOS users

## Code Style

- Use early returns to avoid nested conditionals
- Add blank lines between variable declarations and control flow/function calls
- Use `??` instead of `||` for nullish coalescing in TypeScript
- Follow immutability patterns; avoid mutable objects/classes
- Single responsibility per function
- Function names: verbs / Variable names: nouns
