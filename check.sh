#!/usr/bin/env bash
# Sends several requests in parallel to the proxy and shows which key handled each.
# Usage: ./check.sh [number_of_requests]     (default 6)
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

PORT="${PORT:-4000}"
N="${1:-6}"
URL="http://localhost:${PORT}"

if ! curl -fsS "$URL/health/liveliness" >/dev/null 2>&1; then
  echo "Proxy is not reachable on $URL. Start it first with ./start.sh" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Sending $N parallel requests (this can take ~30s, the model thinks first)..."
for i in $(seq 1 "$N"); do
  (
    curl -si "$URL/v1/chat/completions" \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"model":"gemini-main","messages":[{"role":"user","content":"say hi"}]}' \
      > "$tmp/$i" 2>/dev/null || true
  ) &
done
wait

ok=0
ids=""
for i in $(seq 1 "$N"); do
  code="$(head -n1 "$tmp/$i" | awk '{print $2}')"
  id="$(grep -i '^x-litellm-model-id:' "$tmp/$i" | awk '{print $2}' | tr -d '\r' | cut -c1-8)"
  retries="$(grep -i '^x-litellm-attempted-retries:' "$tmp/$i" | awk '{print $2}' | tr -d '\r')"
  printf 'request %-2s  HTTP %-4s  key-id %-8s  retries %s\n' "$i" "${code:-none}" "${id:--}" "${retries:-0}"
  [ "$code" = "200" ] && ok=$((ok + 1))
  [ -n "$id" ] && ids="$ids $id"
done

distinct="$(printf '%s\n' $ids | sort -u | grep -c . || true)"
echo
echo "$ok/$N succeeded, handled by $distinct different key(s)."
if [ "$ok" -lt "$N" ]; then
  echo "Some requests failed. Look at the proxy terminal for the error."
fi
