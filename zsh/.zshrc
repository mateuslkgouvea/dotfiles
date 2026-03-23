export PATH="/opt/homebrew/bin:$PATH"

# pyenv setup
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"

# Aliases
alias python='python3'
alias pip=pip3
alias lzd='lazydocker'
alias lzg='lazygit'
alias vim='nvim'
alias nvc='NVIM_APPNAME=nvchad nvim'
alias lzv='NVIM_APPNAME=lazyvim nvim'

# Variables
if [ -f "$HOME/.zshvars" ]; then
  source "$HOME/.zshvars"
fi

# Starship 
eval "$(starship init zsh)"

# Plugins
source $ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source $ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh

