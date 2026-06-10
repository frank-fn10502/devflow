#!/bin/sh
set -eu

# Keep Gitea's public clone URL host-reachable for browsers and users.
# Clone containers cannot use localhost-style hosts because Git/libcurl treats
# them as loopback inside the clone container. Rewrite only DevFlow's local
# Gitea URLs to the Docker service name.
if [ -z "${PLUGIN_REMOTE:-}" ]; then
  case "${CI_REPO_CLONE_URL:-}" in
    http://gitea.localhost:5200/*)
      export PLUGIN_REMOTE="http://gitea:5200/${CI_REPO_CLONE_URL#http://gitea.localhost:5200/}"
      ;;
    http://localhost:5200/*)
      export PLUGIN_REMOTE="http://gitea:5200/${CI_REPO_CLONE_URL#http://localhost:5200/}"
      ;;
  esac
fi

exec /bin/plugin-git "$@"
