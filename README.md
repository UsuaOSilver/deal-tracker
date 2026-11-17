# deal-tracker

Self-hosted price and restock tracker. Watches chosen product pages, sends a
phone alert when a price drops under its target, and includes a one-tap buy
link. Built on a pinned, hardened build of
[changedetection.io](https://github.com/dgtlmoon/changedetection.io).

Buying stays a human tap. Nothing here purchases anything.

## Run

Needs Docker with Compose and BuildKit.

```sh
cp .env.example .env
python3 scripts/hash-password.py    # paste the SALTED_PASS line into .env
docker compose up -d --build
```

Open http://127.0.0.1:5000 and log in.

## Alerts (Telegram)

1. In Telegram, message `@BotFather`, send `/newbot`, and keep the bot token.
2. Send any message to the new bot, then open
   `https://api.telegram.org/bot<TOKEN>/getUpdates` and note `chat.id`.
3. In the tracker, go to Settings > Notifications and add
   `tgram://<TOKEN>/<CHAT_ID>`, then press "Send test notification".

The token is a secret. It lives only in the tracker's datastore, never in git.

## Hardening

| Item | Where |
| --- | --- |
| Upstream pinned to an exact commit | `UPSTREAM_COMMIT` in `Dockerfile` |
| Base image pinned by digest | `PYTHON_IMAGE` in `Dockerfile` |
| Hash-locked dependencies, Python 3.11 | `requirements.lock` |
| Non-root, read-only root filesystem, no capabilities, no new privileges | `docker-compose.yml` |
| Bound to 127.0.0.1 only | `docker-compose.yml` |
| Password set from the environment and locked | `SALTED_PASS` in `.env` |
| Version check, LLM features and MCP server off | `docker-compose.yml` |
| No runtime package installs (`EXTRA_PACKAGES` ignored) | `Dockerfile` |
| OpenSSL left at its default security level | `Dockerfile` |

## Rules

- Treat the login as a weak boundary. Keep the port on loopback.
- Never use the Share button. It uploads watch settings, including custom
  headers and browser steps.
- No store logins, cards or payment data inside the tracker.
- Page fetches do not verify TLS, so a tracked price is a hint, not a fact.
  Confirm the price on the store page before buying.
- Secrets live in `.env`, never in git.

## Upgrading

Check upstream [security advisories](https://github.com/dgtlmoon/changedetection.io/security/advisories)
weekly. To move to a new upstream commit:

1. Review the upstream changes since the current pin.
2. Set `UPSTREAM_COMMIT` in `Dockerfile` and the image tag in `docker-compose.yml`.
3. Run `scripts/update-lock.sh` (needs [uv](https://docs.astral.sh/uv/)) and review the diff.
4. `docker compose up -d --build`

Known open item: `soupsieve` 2.10 has three low-risk slowdown bugs. Upgrade
once `beautifulsoup4` allows a fixed version.
