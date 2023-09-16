# dotfiles

### Get Started

#### Prerequisites

- curl wget fzf zsh tmux git make gcc g++ bat nodejs npm nvm openssh
  - mac
    - brew install curl wget fzf zsh tmux git make gcc bat nodejs npm nvm awscli helm
- helm diff plugin
- ssh-keygen -t rsa -C "socoolbear"
  - cat ~/.ssh/id_rsa.pub ----> add github.com SSH key
- mkdir -p ~/code  ~/.local/bin
- kitty, nerd fonts
  - ssh remote tmux error fix
    - ~/.ssh/config : SetEnv TERM=xterm
  - https://github.com/ronniedroid/getnf
    - JetBrainsMono
- zsh + oh-my-zshell
    - zsh-autosuggestions
    - zsh-syntax-highlighting
- httpie

#### optional

- oh-my-zshell
    - agnoster theme : [multi line setting](https://gist.github.com/socoolbear/d59447cfaffc24ee914e27fe3019cd81)
- Karabiner-Elements
- git-secret gnupg
- lunar vim install
    - install.sh : unblock lunar vim
    - lazy.git

#### Install

```shell
git clone https://github.com/socoolbear/dotfiles.git ~/.dotfiles

${HOME}/dotfiles/install
```