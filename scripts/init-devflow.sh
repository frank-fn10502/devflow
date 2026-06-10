#!/bin/sh
set -eu

# First-run initializer for DevFlow.
#
# Design goal:
#   .env is the single source of truth for the first admin username.
#   The script creates that username as a Gitea admin, while docker-compose.yml
#   passes the same username to Woodpecker as WOODPECKER_ADMIN.
#
# This avoids the dangerous split-brain case where Gitea admin and Woodpecker
# admin are typed separately and drift apart.

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="${ENV_FILE:-.env}"
ENV_SOURCE="$ENV_FILE"
case "$ENV_SOURCE" in
  /*|*/*) ;;
  *) ENV_SOURCE="./$ENV_SOURCE" ;;
esac

is_placeholder() {
  case "${1:-}" in
    ""|replace-with-*|your-*) return 0 ;;
    *) return 1 ;;
  esac
}

require_env() {
  name="$1"
  value="$(eval "printf '%s' \"\${$name:-}\"")"

  if is_placeholder "$value"; then
    printf 'Missing required %s in %s\n' "$name" "$ENV_FILE" >&2
    exit 1
  fi
}

gitea_user_exists() {
  docker exec --user git gitea gitea admin user list \
    | awk 'NR > 1 {print $2}' \
    | grep -Fx "$GITEA_ADMIN_USERNAME" >/dev/null
}

gitea_is_installed() {
  docker exec --user git gitea sh -c \
    "grep -Eq '^INSTALL_LOCK[[:space:]]*=[[:space:]]*true$' /data/gitea/conf/app.ini"
}

install_gitea_if_needed() {
  if gitea_is_installed; then
    printf '%s\n' 'Gitea is already installed.'
    return 0
  fi

  printf '%s\n' 'Installing Gitea for first use...'

  # Stop the web process before running migrations from a one-off container.
  docker compose stop gitea

  # The Gitea image creates a starter app.ini on first web boot. Complete it
  # here so CLI admin-user creation works without visiting the install page.
  docker compose run --rm --no-deps --user git --entrypoint sh gitea -c '
    set -eu

    SECRET_KEY="$(gitea generate secret SECRET_KEY)"
    INTERNAL_TOKEN="$(gitea generate secret INTERNAL_TOKEN)"
    OAUTH2_JWT_SECRET="$(gitea generate secret JWT_SECRET)"
    LFS_JWT_SECRET="$(gitea generate secret LFS_JWT_SECRET)"

    export GITEA__security__INSTALL_LOCK=true
    export GITEA__security__SECRET_KEY="$SECRET_KEY"
    export GITEA__security__INTERNAL_TOKEN="$INTERNAL_TOKEN"
    export GITEA__oauth2__JWT_SECRET="$OAUTH2_JWT_SECRET"
    export GITEA__server__LFS_START_SERVER=true
    export GITEA__server__LFS_JWT_SECRET="$LFS_JWT_SECRET"

    gitea config edit-ini --config /data/gitea/conf/app.ini --apply-env --in-place
    gitea migrate --config /data/gitea/conf/app.ini
  '

  docker compose up -d gitea
  wait_for_gitea
}

wait_for_gitea() {
  printf '%s\n' 'Waiting for Gitea...'

  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS http://localhost:5200 >/dev/null 2>&1; then
      printf '%s\n' 'Gitea is ready.'
      return 0
    fi

    i=$((i + 1))
    sleep 2
  done

  printf '%s\n' 'Timed out waiting for Gitea at http://localhost:5200' >&2
  exit 1
}

if [ ! -f "$ENV_FILE" ]; then
  printf 'Missing %s. Create it first:\n' "$ENV_FILE" >&2
  printf '%s\n' '  cp .env.example .env' >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_SOURCE"

require_env GITEA_ADMIN_USERNAME
require_env WOODPECKER_AGENT_SECRET

./scripts/create-external-volumes.sh

# Gitea must exist before its admin user can be created.
docker compose up -d gitea
wait_for_gitea
install_gitea_if_needed

if gitea_user_exists; then
  printf 'exists  Gitea admin user %s\n' "$GITEA_ADMIN_USERNAME"
else
  require_env GITEA_ADMIN_EMAIL
  require_env GITEA_ADMIN_PASSWORD

  docker exec --user git gitea gitea admin user create \
    --username "$GITEA_ADMIN_USERNAME" \
    --email "$GITEA_ADMIN_EMAIL" \
    --password "$GITEA_ADMIN_PASSWORD" \
    --admin \
    --must-change-password=false

  printf 'created Gitea admin user %s\n' "$GITEA_ADMIN_USERNAME"
fi

if is_placeholder "${WOODPECKER_GITEA_CLIENT:-}" || is_placeholder "${WOODPECKER_GITEA_SECRET:-}"; then
  printf '\n%s\n' 'Gitea admin is ready, but Woodpecker OAuth is not configured yet.'
  printf '%s\n' 'Create a Gitea OAuth2 application with this redirect URI:'
  printf '%s\n' '  http://localhost:5201/authorize'
  printf '%s\n' 'Then fill WOODPECKER_GITEA_CLIENT and WOODPECKER_GITEA_SECRET in .env,'
  printf '%s\n' 'and run this script again to start Woodpecker.'
  exit 0
fi

# Build the local clone wrapper before starting Woodpecker. The wrapper lets
# Gitea keep public gitea.localhost clone URLs while CI containers clone through
# the Docker-network service name gitea:5200.
docker compose build woodpecker-git-clone-localhost

docker compose up -d woodpecker-server woodpecker-agent

printf '\n%s\n' 'DevFlow is ready.'
printf '%s\n' '  Gitea:       http://gitea.localhost:5200'
printf '%s\n' '  Woodpecker:  http://localhost:5201'
printf '  Admin user:  %s\n' "$GITEA_ADMIN_USERNAME"
