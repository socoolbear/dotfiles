# Dotfiles

### Prerequisites
- curl wget fzf zsh tmux git make gcc g++ bat nodejs npm nvm openssh
  - mac
    - brew install curl wget fzf zsh tmux git make gcc bat nodejs npm nvm awscli
- enable "1password ssh agent"
  - or 
    - ssh-keygen -t rsa -C "socoolbear"
    - cat ~/.ssh/id_rsa.pub ----> add github.com SSH key
- mkdir -p ~/code  ~/.local/bin
- zsh + oh-my-zshell
  - zsh-autosuggestions
  - zsh-syntax-highlighting
- kitty, nerd fonts
  - ssh remote tmux error fix
    - ~/.ssh/config : SetEnv TERM=xterm
  - https://github.com/ronniedroid/getnf
    - JetBrainsMono

#### optional
- mac accent popup disable  ( when keyboard long press ) 
```shell
    defaults write -g ApplePressAndHoldEnabled -bool false
```
- oh-my-zshell
    - agnoster theme : [multi line setting](https://gist.github.com/socoolbear/d59447cfaffc24ee914e27fe3019cd81)
- Karabiner-Elements
- git include

## Install

```shell
git clone https://github.com/socoolbear/dotfiles.git ~/.dotfiles

${HOME}/dotfiles/install
```

## etc apps
- slack, forti-client, jetbrains, notion, obsidian, postman, zoom,
- rectangle, alfred, 1password, discord, google-chrome, figma,
- claude code, claude desktop, gpt desktop
- docker, runcat

## post
- copy .zsh_history from old
- git
  - set global name, email
  - split account  : .gitconfig > IncludeIf
- alfred : plugin setting
- obsidean : valute setting
- forti-client : vpn setting
 