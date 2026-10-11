#!/usr/bin/env bash
# Starts the local LiteLLM proxy on http://localhost:4000
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$DIR"
export PATH="$HOME/.local/bin:$PATH"

if [ ! -f .env ]; then
  echo "No .env found. Run ./install.sh first." >&2
  exit 1
fi
if ! command -v litellm >/dev/null 2>&1; then
  echo "litellm not found. Run ./install.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

./generate-config.sh

PORT="${PORT:-4000}"
echo "Starting LiteLLM proxy on http://localhost:${PORT} (Ctrl+C to stop)"
exec litellm --config litellm_config.yaml --port "$PORT"
