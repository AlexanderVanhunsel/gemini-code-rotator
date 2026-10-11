#!/usr/bin/env bash
# Lists the Gemini models your first key can use, in the format GEMINI_MODEL expects.
# Usage: ./list-models.sh [filter]     (default filter: flash)
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$DIR"

if [ ! -f .env ]; then
  echo "No .env found. Run ./install.sh first." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

FILTER="${1:-flash}"

curl -fsS -H "x-goog-api-key: ${GEMINI_API_KEY_1:?GEMINI_API_KEY_1 is not set in .env}" \
  "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200" \
  | grep '"name"' \
  | sed -E 's/.*"models\/([^"]+)".*/gemini\/\1/' \
  | grep -i -- "$FILTER" || true

echo
echo "Copy one of the lines above into GEMINI_MODEL in .env, then restart ./start.sh"
