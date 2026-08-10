#!/usr/bin/env bash
set -euo pipefail

PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
DB="${1:-postgres}"
export PGPASSWORD

if command -v psql >/dev/null 2>&1; then
  : "${PGHOST:=127.0.0.1}"
  : "${PGPORT:=5432}"
  export PGHOST PGPORT PGUSER
  exec psql -v ON_ERROR_STOP=1 -d "$DB"
fi

if command -v docker >/dev/null 2>&1; then
  name="terranex-db-shell"
  if ! docker inspect "$name" >/dev/null 2>&1; then
    docker run -d \
      --name "$name" \
      -e POSTGRES_USER="$PGUSER" \
      -e POSTGRES_PASSWORD="$PGPASSWORD" \
      -e POSTGRES_DB=postgres \
      postgres:16-alpine >/dev/null
  elif [[ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]]; then
    docker start "$name" >/dev/null
  fi

  for _ in $(seq 1 60); do
    docker exec "$name" pg_isready -U "$PGUSER" -d postgres >/dev/null 2>&1 && break
    sleep 1
  done

  exec docker exec -it "$name" psql -U "$PGUSER" -d "$DB"
fi

echo "ERROR: neither psql nor docker is available. Database work cannot proceed in this environment." >&2
exit 2
