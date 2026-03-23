# Variables
TMUX_CONF_DIR=~/.cofig/tmux

## GIT
## create  signingkey ~/.ssh/id_ed25519_gh_sign.pub if doesnt exits
git_keys=("id_ed25519_gh_sign", "id_ed25519_gh")

for key_name in "${git_keys[@]}"; do
  key_path="$HOME/.ssh/$key_name"
  if [ ! -f "$key_path" ]; then
    ssh-keygen -t ed25519 -f "$key_path" -N "" -q
  fi
done

# TMUX
if [ -d "$(TMUX_CONF_DIR)/plugins/tpm"]; then
  git clone https://github.com/tmux-plugins/tpm "${TMUX_CONF_DIR}/plugins/tpm"
fi
tmux source-file "${TMUX_CONF_DIR}/tmux.conf"
