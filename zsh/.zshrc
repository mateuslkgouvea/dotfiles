export PATH="/opt/homebrew/bin:$PATH"
export EDITOR=nvim

# pyenv setup
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"

# Aliases
alias python='python3'
alias pip=pip3
alias lzd='lazydocker'
alias lzg='lazygit'
alias vim='nvim'
alias nvc='NVIM_APPNAME=nvchad nvim'
alias lzv='NVIM_APPNAME=lazyvim nvim'
alias ghd='gh dash'

# Variables
if [ -f "$HOME/.zshvars" ]; then
  source "$HOME/.zshvars"
fi

# Starship 
eval "$(starship init zsh)"

# Plugins

if [ -n "$ZSH_PLUGIN_DIR" ] && [ -d "$ZSH_PLUGIN_DIR" ]; then
  plugins=(
    zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    zsh-autosuggestions/zsh-autosuggestions.zsh
  )

  for plugin in "${plugins[@]}"; do
    file="$ZSH_PLUGIN_DIR/$plugin"
    [ -f "$file" ] && source "$file"
  done
fi

