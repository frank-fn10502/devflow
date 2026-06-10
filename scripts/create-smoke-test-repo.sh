#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="${ENV_FILE:-.env}"
REPO_NAME="${SMOKE_REPO_NAME:-woodpecker-smoke-test}"
TARGET_DIR="${SMOKE_REPO_DIR:-$REPO_NAME}"
TEMPLATE_DIR="${SMOKE_TEMPLATE_DIR:-templates/woodpecker-smoke-test}"
CLEANUP_FILES=""

cleanup() {
  if [ -n "$CLEANUP_FILES" ]; then
    rm -f $CLEANUP_FILES
  fi
}

trap cleanup EXIT INT TERM

make_temp_file() {
  file="$(mktemp)"
  CLEANUP_FILES="${CLEANUP_FILES}${CLEANUP_FILES:+ }$file"
  printf '%s\n' "$file"
}

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

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

wait_for_gitea() {
  printf '%s\n' 'Waiting for Gitea...'

  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS "$GITEA_URL" >/dev/null 2>&1; then
      printf '%s\n' 'Gitea is ready.'
      return 0
    fi

    i=$((i + 1))
    sleep 2
  done

  printf 'Timed out waiting for Gitea at %s\n' "$GITEA_URL" >&2
  exit 1
}

create_remote_repo() {
  body_file="$(make_temp_file)"
  netrc_file="$(make_temp_file)"
  {
    printf 'machine %s\n' "$GITEA_NETRC_MACHINE"
    printf 'login %s\n' "$GITEA_ADMIN_USERNAME"
    printf 'password %s\n' "$GITEA_ADMIN_PASSWORD"
  } >"$netrc_file"
  chmod 600 "$netrc_file"

  http_code="$(
    curl -sS -o "$body_file" -w '%{http_code}' \
      --netrc-file "$netrc_file" \
      -H 'Content-Type: application/json' \
      -X POST "$GITEA_URL/api/v1/user/repos" \
      -d "{\"name\":\"$(json_escape "$REPO_NAME")\",\"private\":false,\"auto_init\":false}" \
      || true
  )"

  case "$http_code" in
    201)
      printf 'created Gitea repository %s/%s\n' "$GITEA_ADMIN_USERNAME" "$REPO_NAME"
      ;;
    409)
      printf 'exists  Gitea repository %s/%s\n' "$GITEA_ADMIN_USERNAME" "$REPO_NAME"
      ;;
    *)
      printf 'Failed to create Gitea repository. HTTP status: %s\n' "${http_code:-unknown}" >&2
      sed 's/^/  /' "$body_file" >&2
      exit 1
      ;;
  esac
}

ensure_target_absent() {
  if [ -e "$TARGET_DIR" ]; then
    printf 'Refusing to overwrite existing %s\n' "$TARGET_DIR" >&2
    printf '%s\n' 'Move it aside or set SMOKE_REPO_DIR to another path.' >&2
    exit 1
  fi
}

init_local_repo() {
  mkdir -p "$TARGET_DIR"
  cp -R "$TEMPLATE_DIR/." "$TARGET_DIR/"
  chmod +x "$TARGET_DIR/scripts/smoke.sh"

  git -C "$TARGET_DIR" init -b main
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -m 'Add Woodpecker smoke test'
}

push_local_repo() {
  remote_url="$GITEA_URL/$GITEA_ADMIN_USERNAME/$REPO_NAME.git"
  askpass_file="$(make_temp_file)"
  username_file="$(make_temp_file)"
  password_file="$(make_temp_file)"

  printf '%s\n' "$GITEA_ADMIN_USERNAME" >"$username_file"
  printf '%s\n' "$GITEA_ADMIN_PASSWORD" >"$password_file"
  chmod 600 "$username_file" "$password_file"

  cat >"$askpass_file" <<'ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) cat "$DEVFLOW_GIT_USERNAME_FILE" ;;
  *Password*) cat "$DEVFLOW_GIT_PASSWORD_FILE" ;;
  *) printf '\n' ;;
esac
ASKPASS
  chmod 700 "$askpass_file"

  git -C "$TARGET_DIR" remote add origin "$remote_url"
  DEVFLOW_GIT_USERNAME_FILE="$username_file" \
    DEVFLOW_GIT_PASSWORD_FILE="$password_file" \
    GIT_ASKPASS="$askpass_file" \
    GIT_TERMINAL_PROMPT=0 \
    git -C "$TARGET_DIR" push -u origin main
}

if [ ! -f "$ENV_FILE" ]; then
  printf 'Missing %s. Create it first:\n' "$ENV_FILE" >&2
  printf '%s\n' '  cp .env.example .env' >&2
  exit 1
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
  printf 'Missing smoke test template: %s\n' "$TEMPLATE_DIR" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

require_env GITEA_ADMIN_USERNAME
require_env GITEA_ADMIN_PASSWORD

GITEA_URL="${GITEA_SMOKE_GITEA_URL:-${WOODPECKER_EXPERT_FORGE_OAUTH_HOST:-http://gitea.localhost:5200}}"
GITEA_URL="${GITEA_URL%/}"
GITEA_NETRC_MACHINE="${GITEA_URL#*://}"
GITEA_NETRC_MACHINE="${GITEA_NETRC_MACHINE%%/*}"
GITEA_NETRC_MACHINE="${GITEA_NETRC_MACHINE%%:*}"

ensure_target_absent
wait_for_gitea
create_remote_repo
init_local_repo
push_local_repo

printf '\n%s\n' 'Woodpecker smoke test repository is ready.'
printf '  Local repo:  %s\n' "$TARGET_DIR"
printf '  Gitea repo:  %s/%s/%s\n' "$GITEA_URL" "$GITEA_ADMIN_USERNAME" "$REPO_NAME"
printf '%s\n' 'Enable the repository in Woodpecker, then push another commit to trigger a run.'
