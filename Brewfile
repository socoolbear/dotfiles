# Brewfile — Dotfiles 코어 패키지 (CLI / formula / tap)
# 사용법:
#   make brew         # 본 파일 적용 (코어)
#   make brew-apps    # GUI 앱 (Brewfile.apps) 적용 (선택)
#
# 새 leaf 가 생기면 시드 재생성:
#   brew bundle dump --describe --force --file=Brewfile.seed
# 그 후 본 파일과 비교해 수동 정리.
#
# 참고:
# - GUI cask 는 Brewfile.apps 로 분리
# - 회사 전용 추가 도구: Brewfile.work (.gitignore 됨)
# - 호스트 로컬: Brewfile.local (.gitignore 됨)

#--------------------------------------------------------------------------
# 시스템 / 코어
#--------------------------------------------------------------------------

# Get a file from an HTTP, HTTPS or FTP server
brew "curl"
# Internet file retriever
brew "wget"
# GNU compiler collection
brew "gcc"
# Utility for directing compilation
brew "make"
# UNIX shell (command interpreter)
brew "zsh"
# Terminal multiplexer
brew "tmux"
# Distributed revision control system
brew "git"
# Mac App Store CLI (Brewfile.apps 의 mas 항목 사용 시 필요)
brew "mas"

#--------------------------------------------------------------------------
# 검색 / 파일 (코어 대체)
#--------------------------------------------------------------------------

# Search tool like grep and The Silver Searcher (ripgrep)
brew "ripgrep"
# Simple, fast and user-friendly alternative to find
brew "fd"
# Clone of cat(1) with syntax highlighting and Git integration
brew "bat"
# Modern, maintained replacement for ls
brew "eza"
# Shell extension to navigate your filesystem faster
brew "zoxide"

#--------------------------------------------------------------------------
# 검색 / 히스토리
#--------------------------------------------------------------------------

# Command-line fuzzy finder written in Go
brew "fzf"
# Improved shell history for zsh, bash, fish and nushell
brew "atuin"

#--------------------------------------------------------------------------
# 데이터 처리
#--------------------------------------------------------------------------

# Lightweight and flexible command-line JSON processor
brew "jq"
# Process YAML, JSON, XML, CSV and properties documents from the CLI
brew "yq"
# User-friendly cURL replacement (oh-my-zsh httpie plugin 이 사용)
brew "httpie"

#--------------------------------------------------------------------------
# 코드 품질 / 린트
#--------------------------------------------------------------------------

# Code searching, linting, rewriting (AST 기반)
brew "ast-grep"
# Diff that understands syntax
brew "difftastic"
# Static analysis and lint tool, for (ba)sh scripts
brew "shellcheck"
# Autoformat shell script source code
brew "shfmt"
# Extremely fast Python linter, written in Rust
brew "ruff"

#--------------------------------------------------------------------------
# Git / TUI
#--------------------------------------------------------------------------

# GitHub command-line tool
brew "gh"
# Syntax-highlighting pager for git and diff output
brew "git-delta"
# Simple terminal UI for git commands
brew "lazygit"
# Blazing fast terminal file manager written in Rust, based on async I/O
brew "yazi"

#--------------------------------------------------------------------------
# 프롬프트 / 알림
#--------------------------------------------------------------------------

# Cross-shell prompt for astronauts
brew "starship"
# Send macOS User Notifications from the command-line
brew "terminal-notifier"

#--------------------------------------------------------------------------
# 클라우드 / DevOps
#--------------------------------------------------------------------------

# Official Amazon AWS command-line interface
brew "awscli"
# Kubernetes package manager
brew "helm"
# Run a Kubernetes cluster locally
brew "minikube"
# Database version control to control migrations
brew "flyway"
# Kubernetes CLI To Manage Your Clusters In Style!
brew "k9s"
# Secure introspectable tunnels to localhost (cask 로 배포)
cask "ngrok"

#--------------------------------------------------------------------------
# 데이터베이스
#--------------------------------------------------------------------------

# MySQL client (zshrc PATH 에 포함)
brew "mysql-client"
# Persistent key-value database, with built-in net interface
brew "redis"

#--------------------------------------------------------------------------
# 언어 / 런타임 — 버전 매니저
#--------------------------------------------------------------------------

# Polyglot runtime manager (Node, Go 등 통합. nvm/rbenv 대체).
# 글로벌 매니페스트: dotfiles/mise/config.toml → ~/.config/mise/config.toml
brew "mise"

#--------------------------------------------------------------------------
# 언어 / 런타임 — Node
#--------------------------------------------------------------------------
# Node 런타임 자체는 mise (mise/config.toml) 로 관리. 패키지 매니저만 brew.

# Fast, disk space efficient package manager
brew "pnpm"
# JavaScript package manager
brew "yarn"
# Incredibly fast JavaScript runtime, bundler, transpiler and package manager
brew "bun"

#--------------------------------------------------------------------------
# 언어 / 런타임 — Python
#--------------------------------------------------------------------------

# Interpreted, interactive, object-oriented programming language
brew "python@3.14"
# Python interface to Tcl/Tk
brew "python-tk@3.14"

#--------------------------------------------------------------------------
# 언어 / 런타임 — PHP
#--------------------------------------------------------------------------

# General-purpose scripting language
brew "php"
# Dependency Manager for PHP
brew "composer"

#--------------------------------------------------------------------------
# 모바일 / iOS
#--------------------------------------------------------------------------

# Dependency manager for Cocoa projects
brew "cocoapods"

#--------------------------------------------------------------------------
# 문서 / 변환
#--------------------------------------------------------------------------

# Swiss-army knife of markup format conversion
brew "pandoc"
# Convert HTML to PDF
brew "weasyprint"
# PDF rendering library (based on the xpdf-3.0 code base)
brew "poppler"

#--------------------------------------------------------------------------
# AI / 코딩 에이전트
#--------------------------------------------------------------------------

# OpenAI's coding agent that runs in your terminal
cask "codex"
# Anthropic's official CLI for Claude
cask "claude-code"
