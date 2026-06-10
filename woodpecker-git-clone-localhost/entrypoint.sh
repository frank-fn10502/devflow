#!/bin/sh
set -eu

# Keep Gitea's public clone URL as gitea.localhost for browsers and users.
# The clone container itself cannot use gitea.localhost because Git/libcurl
# treats *.localhost as loopback. If Woodpecker did not already provide a custom
# remote, rewrite only the DevFlow gitea.localhost URL to the Docker service name.
if [ -z "${PLUGIN_REMOTE:-}" ]; then
  case "${CI_REPO_CLONE_URL:-}" in
    http://gitea.localhost:5200/*)
      export PLUGIN_REMOTE="http://gitea:5200/${CI_REPO_CLONE_URL#http://gitea.localhost:5200/}"
      ;;
  esac
fi

exec /bin/plugin-git "$@"
