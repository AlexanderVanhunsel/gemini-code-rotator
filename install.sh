#!/usr/bin/env bash
# gemini-code-rotator installer
#
#   ./install.sh          full install: tools, API keys, Aider config
#   ./install.sh --keys   only re-enter your API keys (no package install)
#
# Keys are written ONLY to ./.env on this machine (chmod 600, git-ignored).
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$DIR"
export PATH="$HOME/.local/bin:$PATH"

MODE="full"
case "${1:-}" in
  "") ;;
  --keys) MODE="keys" ;;
  -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# ---------------------------------------------------------------- packages --
install_packages() {
  say "Installing system packages and pipx"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y curl git python3-venv pipx \
      || { warn "apt could not install pipx, falling back to pip"; \
           sudo apt-get install -y python3-pip && \
           python3 -m pip install --user --break-system-packages pipx; }
  elif command -v brew >/dev/null 2>&1; then
    brew install pipx
  elif ! command -v pipx >/dev/null 2>&1; then
    echo "Could not find apt or brew, and pipx is not installed." >&2
    echo "Install pipx manually (https://pipx.pypa.io) and re-run ./install.sh" >&2
    exit 1
  fi
  pipx ensurepath >/dev/null 2>&1 || true

  say "Installing Aider"
  # aider-install fetches a compatible Python (3.12). Plain 'pipx install aider-chat'
  # fails on very new system Pythons because of an old numpy pin.
  if command -v aider >/dev/null 2>&1; then
    echo "aider already installed, skipping"
  else
    pipx install aider-install
    aider-install
  fi

  say "Installing LiteLLM (with proxy support)"
  if pipx list --short 2>/dev/null | grep -q '^litellm '; then
    echo "litellm already installed, skipping"
  else
    pipx install 'litellm[proxy]'
  fi
}

# -------------------------------------------------------------------- keys --
read_existing() { # read_existing VAR -> value from .env, or empty
  [ -f .env ] || return 0
  grep -E "^$1=" .env | head -n1 | cut -d= -f2- || true
}

prompt_keys() {
  say "Google Gemini API keys"
  echo "Create one key per Google Cloud project at https://aistudio.google.com/apikey"
  echo "(choose 'Create API key in new project' each time - keys in the same"
  echo "project share one quota and will not rotate usefully)."
  echo

  local count
  read -rp "How many keys do you want to add? [3] " count
  count="${count:-3}"
  case "$count" in
    ''|*[!0-9]*|0) echo "Please enter a positive number." >&2; exit 1 ;;
  esac

  local keys=() k i
  for i in $(seq 1 "$count"); do
    read -rsp "Paste API key $i (input is hidden): " k
    echo
    k="$(printf '%s' "$k" | tr -d '[:space:]')"
    if [ -z "$k" ]; then echo "Empty key, aborting." >&2; exit 1; fi
    case "$k" in AIza*) ;; *) warn "Key $i does not start with 'AIza' - double check it." ;; esac
    keys+=("$k")
  done

  local master model port
  master="$(read_existing LITELLM_MASTER_KEY)"
  if [ -z "$master" ] || [ "$master" = "sk-local-change-me" ]; then
    master="sk-local-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  model="$(read_existing GEMINI_MODEL)"
  model="${model:-gemini/gemini-3.8-flash}"
  port="$(read_existing PORT)"

  umask 077
  {
    i=1
    for k in "${keys[@]}"; do
      echo "GEMINI_API_KEY_$i=$k"
      i=$((i + 1))
    done
    echo "GEMINI_MODEL=$model"
    echo "LITELLM_MASTER_KEY=$master"
    if [ -n "$port" ]; then echo "PORT=$port"; fi
  } > .env
  chmod 600 .env
  echo "Saved ${#keys[@]} key(s) to $DIR/.env (readable only by you)."
}

# ------------------------------------------------------------ aider config --
write_aider_config() {
  local master port target="$HOME/.aider.conf.yml"
  master="$(read_existing LITELLM_MASTER_KEY)"
  port="$(read_existing PORT)"; port="${port:-4000}"

  if [ -f "$target" ]; then
    local backup="$target.bak.$(date +%Y%m%d%H%M%S)"
    cp "$target" "$backup"
    warn "Existing ~/.aider.conf.yml backed up to $backup"
  fi
  umask 077
  sed -e "s#__PORT__#$port#" -e "s#__MASTER_KEY__#$master#" aider.conf.template.yml > "$target"
  chmod 600 "$target"
  echo "Wrote $target"
}

# -------------------------------------------------------------------- main --
if [ "$MODE" = "full" ]; then
  install_packages
fi

if [ "$MODE" = "keys" ] || [ ! -f .env ] || [ -z "$(read_existing GEMINI_API_KEY_1)" ]; then
  prompt_keys
else
  say "Existing .env found - keeping your keys (use ./install.sh --keys to replace them)"
fi

chmod +x ./*.sh
./generate-config.sh
write_aider_config

say "Done!"
cat <<EOF

Next steps:
  1. Start the proxy (leave this terminal open):   ./start.sh
  2. In another terminal, go to a git project:     cd ~/my-project && aider
  3. Optional - verify the key rotation:           ./check.sh

If 'aider' or 'litellm' is not found, open a new terminal (or run: source ~/.bashrc).
EOF
