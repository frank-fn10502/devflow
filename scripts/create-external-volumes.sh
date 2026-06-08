#!/bin/sh
set -eu

# DevFlow keeps persistent service data in external Docker volumes.
#
# The volumes are declared as `external: true` in docker-compose.yml so Docker
# Compose does not own them. This protects Git repositories, Gitea metadata,
# and Woodpecker CI state from accidental deletion via:
#
#   docker compose down -v
#
# This script is intentionally idempotent. It can be run before every startup:
# existing volumes are left untouched, and missing volumes are created.

create_volume_if_missing() {
  volume_name="$1"

  if docker volume inspect "$volume_name" >/dev/null 2>&1; then
    printf 'exists  %s\n' "$volume_name"
  else
    docker volume create "$volume_name" >/dev/null
    printf 'created %s\n' "$volume_name"
  fi
}

printf '%s\n' 'Checking DevFlow external volumes...'
create_volume_if_missing devflow_gitea-data
create_volume_if_missing devflow_woodpecker-server-data
create_volume_if_missing devflow_woodpecker-agent-config
printf '%s\n' 'External volumes are ready.'
