#!/bin/sh
# End-to-end smoke test: start gizmosql_server, connect to it with
# gizmosql_client, run a query, and verify the result.
#
# Usage: e2e-test.sh /path/to/gizmosql_server /path/to/gizmosql_client [port]
set -eu

SERVER="$1"
CLIENT="$2"
PORT="${3:-31400}"

"$SERVER" --password tiger --port "$PORT" &
SERVER_PID=$!
# Reap the server on exit so the next invocation can bind its ports
# (the server always claims the health port too, regardless of --port).
trap 'kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true' EXIT INT TERM

# The server needs a moment to start listening; retry for up to 30s.
OUT=""
i=0
until OUT="$(GIZMOSQL_PASSWORD=tiger "$CLIENT" --host localhost --port "$PORT" \
  --username gizmosql_user --quiet --csv --command 'SELECT 1 AS one' 2>&1)"; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then
    echo "error: client could not connect after ${i} attempts" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
  fi
  sleep 1
done

printf '%s\n' "$OUT"
if ! printf '%s\n' "$OUT" | grep -qx '1'; then
  echo "error: expected query result '1' not found in client output" >&2
  exit 1
fi
echo "E2E OK: installed server answered SELECT 1 via installed client"
