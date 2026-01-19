# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository for macOS development environment configuration. It manages configurations for zsh, vim, tmux, git, kitty terminal, LunarVim, Karabiner-Elements, and Claude Code.

## Common Commands

```bash
# Install dotfiles (creates symlinks)
./install.sh

# Backup existing dotfiles
./backup.sh
```

## Repository Structure

- `zsh/` - Zsh configuration with Oh My Zsh
- `vim/` - Vim/GVim configurations
- `tmux/` - Tmux configuration with TPM plugins
- `git/` - Git config and global gitignore
- `kitty/` - Kitty terminal configuration
- `lvim/` - LunarVim configuration
- `karabiner/` - Karabiner-Elements keyboard remapping
- `idea/` - IdeaVim configuration for JetBrains IDEs
- `claude/` - Claude Code settings
- `copilot/` - GitHub Copilot instructions
- `nvm/` - NVM default packages

## Symlink Mapping

The `install.sh` script creates these symlinks:
- `zsh/zshrc` → `~/.zshrc`
- `vim/vimrc` → `~/.vimrc`
- `vim/gvimrc` → `~/.gvimrc`
- `idea/ideavimrc` → `~/.ideavimrc`
- `tmux/tmux.conf` → `~/.tmux.conf`
- `claude/settings.json` → `~/.claude/settings.json`
- `kitty/` → `~/.config/kitty`
- `lvim/` → `~/.config/lvim`
- `karabiner/` → `~/.config/karabiner`
- `nvm/default-packages` → `~/.nvm/default-packages`

## Language and Response Guidelines

- Respond in Korean when possible (가능한 한 한국어로 답변)
- Target macOS users
- Git commit messages should be in Korean
- When mixing English and Korean, add space between them (e.g., "Dockerfile 에서" not "Dockerfile에서")

## Code Style

- Use early returns to avoid nested conditionals
- Add blank lines between variable declarations and control flow/function calls
- Use `??` instead of `||` for nullish coalescing in TypeScript
- Follow immutability patterns; avoid mutable objects/classes
- Functions should have single responsibility
- Function names should be verbs; variable names should be nouns
