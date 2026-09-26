# .zshrc — OpenWrt 终端配置

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="ys"
DISABLE_AUTO_UPDATE="true"

plugins=(git command-not-found extract z zsh-syntax-highlighting zsh-autosuggestions zsh-completions)

source $ZSH/oh-my-zsh.sh

# Aliases
alias ll='ls -lAhF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'
alias vi='vim'

autoload -U compinit && compinit