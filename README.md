# DevFlow

Personal development workflow services managed by Docker Compose.

This stack currently uses Gitea as the Git server and Woodpecker for CI/CD. The directory is intentionally named around the workflow rather than the tool, so the stack can evolve later if the Git server changes.

## Start

Create the external volumes first:

```sh
./scripts/create-external-volumes.sh
```

These volumes are external on purpose:

```text
devflow_gitea-data
devflow_woodpecker-server-data
devflow_woodpecker-agent-config
```

Because they are external, `docker compose down -v` will not delete the Git server and CI/CD data. Do not remove `external: true` unless you are intentionally rebuilding the stack from scratch.

Then start the stack:

```sh
cp .env.example .env
docker compose up -d
```

## Image Versions

Use exact stable image tags in `docker-compose.yml`. Do not use floating tags such as `latest`, `stable`, `1`, or `v3`; those can change underneath the same compose file and unexpectedly trigger database migrations or behavior changes.

Current pinned versions:

```text
Gitea       docker.gitea.com/gitea:1.26.2
Woodpecker  woodpeckerci/woodpecker-server:v3.15.0
Woodpecker  woodpeckerci/woodpecker-agent:v3.15.0
```

When upgrading, read the release notes first, update the tags deliberately, then restart the stack.

## URLs

DevFlow uses the `52xx` host port range:

- Gitea Web: http://localhost:5200
- Gitea SSH: `ssh://git@localhost:5222/...`
- Woodpecker: http://localhost:5201

## Port Allocation

DevFlow reserves host ports in the `52xx` range so related development workflow services stay visually grouped and easy to scan in Docker, firewall, reverse proxy, and documentation settings.

Current allocation:

```text
5200  Gitea Web UI and HTTP Git endpoint
5201  Woodpecker Web UI and webhook endpoint
5222  Gitea SSH Git endpoint
```

When adding new services to this compose stack, prefer the next nearby `52xx` port instead of unrelated defaults such as `3000`, `8000`, or `8080`. Container-internal ports can stay at each image's default; this convention is for host-facing ports.

## Woodpecker OAuth

Create an OAuth2 application in Gitea before signing in to Woodpecker:

- Gitea user OAuth apps: http://localhost:5200/user/settings/applications
- Callback URL: `http://localhost:5201/authorize`

Copy the generated client ID and secret into `.env`:

```sh
WOODPECKER_GITEA_CLIENT=...
WOODPECKER_GITEA_SECRET=...
```

Gitea and Woodpecker data are stored in external Docker volumes.
