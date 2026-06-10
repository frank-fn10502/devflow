# DevFlow

Personal development workflow services managed by Docker Compose.

This stack currently uses Gitea as the Git server and Woodpecker for CI/CD. The directory is intentionally named around the workflow rather than the tool, so the stack can evolve later if the Git server changes.

## Start

Create `.env` from the example and fill the first admin account:

```sh
cp .env.example .env
```

Required first-admin fields:

```text
GITEA_ADMIN_USERNAME
GITEA_ADMIN_EMAIL
GITEA_ADMIN_PASSWORD
```

Use single quotes around `GITEA_ADMIN_PASSWORD`, especially when the password contains spaces or shell-sensitive characters such as `$`, `!`, `#`, `&`, or `;`.

`GITEA_ADMIN_USERNAME` is the single source of truth for the first administrator. The initializer creates this account as the Gitea admin user, and `docker-compose.yml` passes the same value to Woodpecker as `WOODPECKER_ADMIN`.

Run the initializer:

```sh
./scripts/init-devflow.sh
```

The first run creates external Docker volumes, starts Gitea, and creates the Gitea admin user. If Woodpecker OAuth is not configured yet, the script stops after Gitea is ready and prints the next OAuth step. After filling `WOODPECKER_GITEA_CLIENT` and `WOODPECKER_GITEA_SECRET`, run the same script again to start Woodpecker.

The external volumes are:

```text
devflow_gitea-data
devflow_woodpecker-server-data
devflow_woodpecker-agent-config
```

Because they are external, `docker compose down -v` will not delete the Git server and CI/CD data. Do not remove `external: true` unless you are intentionally rebuilding the stack from scratch.

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

- Gitea Web: http://gitea.localhost:5200
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

When adding new services to this compose stack, prefer the next nearby `52xx` port instead of unrelated defaults such as `3000`, `8000`, or `8080`.

Gitea intentionally uses `http://gitea.localhost:5200` instead of `http://gitea:3000` or `http://localhost:5200` as the forge URL. Browser links need a host-reachable URL, while Woodpecker also needs repository metadata to point at the same public forge URL.

The compose file pins the default Docker network to `devflow_default`, and the Woodpecker agent uses `WOODPECKER_BACKEND_DOCKER_NETWORK=devflow_default`, so job containers can reach Gitea by Docker service name.

Woodpecker's default Git clone step needs one extra local fix: Git/libcurl treats `*.localhost` as loopback inside the clone container. DevFlow therefore builds a small local wrapper image, `devflow/woodpecker-git-clone-localhost:2.9.1`, around the pinned `woodpeckerci/plugin-git:2.9.1`. It keeps public Gitea links as `http://gitea.localhost:5200`, but rewrites that clone remote inside CI containers to `http://gitea:5200`.

## Woodpecker OAuth

Create an OAuth2 application in Gitea before signing in to Woodpecker.

1. Open Gitea: http://gitea.localhost:5200
2. Sign in with your Gitea user.
3. Open user settings: http://gitea.localhost:5200/user/settings/applications
4. In "Manage OAuth2 Applications", create a new OAuth2 application.
5. Use these values:

```text
Application Name: Woodpecker
Redirect URI:     http://localhost:5201/authorize
```

6. Copy the generated client ID and client secret into `.env`:

```sh
WOODPECKER_GITEA_CLIENT=...
WOODPECKER_GITEA_SECRET=...
```

7. Run the initializer again:

```sh
./scripts/init-devflow.sh
```

8. Open Woodpecker and sign in with Gitea: http://localhost:5201

Woodpecker admin is derived from `GITEA_ADMIN_USERNAME`; do not set a separate Woodpecker admin username.

Gitea and Woodpecker data are stored in external Docker volumes.
