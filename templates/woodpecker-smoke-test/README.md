# Woodpecker Smoke Test

Minimal repository used to verify that DevFlow can trigger a Woodpecker pipeline from a Gitea push event.

Expected pipeline:

1. Gitea receives a push.
2. Gitea webhook notifies Woodpecker.
3. Woodpecker clones this repository.
4. Woodpecker runs `.woodpecker.yml`.
