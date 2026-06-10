#!/bin/sh
set -eu

printf '%s\n' 'Woodpecker smoke pipeline started.'
test -f README.md
test -f .woodpecker.yml
printf 'Repository: %s\n' "${CI_REPO:-unknown}"
printf 'Commit: %s\n' "${CI_COMMIT_SHA:-unknown}"
printf '%s\n' 'Woodpecker smoke pipeline finished.'
