export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim

# pyenv setup
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"

eval "$(zoxide init zsh)"

# Aliases
alias python='python3'
alias pip=pip3
alias lzd='lazydocker'
alias lzg='lazygit'
# Neovim
alias vim='nvim'
alias nvc='NVIM_APPNAME=nvchad nvim'
alias lzv='NVIM_APPNAME=lazyvim nvim'
alias asv='NVIM_APPNAME=astronvim nvim'
# Misc
alias ghd='gh dash'
alias pgdev='PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres'

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
