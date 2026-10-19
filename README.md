# telegram-bot-api

## Структура Compose

Файлы Docker Compose находятся в `compose/`; основной файл — `compose/docker-compose.yml`.
Команды запускайте из корня проекта через Makefile: он задаёт `--project-directory`
на корень checkout. Build contexts, bind mounts, `env_file` и секреты остаются
относительными к этому корню; имена Compose project, сервисов, сетей и томов сохранены.
При явном вызове Docker используйте `docker compose --project-directory . -f compose/docker-compose.yml ...`.
Если в приватной `.env` или окружении задан `COMPOSE_FILE`, добавьте `compose/`
к прежним именам файлов, сохранив прежний набор overlays и порядок. Для плавного
перехода Make также распознаёт прежние короткие имена, если файлы уже перенесены.
Не меняйте project name и не удаляйте прежние тома для переноса файлов.


## Hostkey Russia: Telegram DC traffic through Finland

The shared API on Russia uses the same pinned Bot API 9.6 image as server,
with a redsocks TCP redirector in the same container. Container-local iptables
redirects only Telegram TCP/443 to SOCKS. NET_ADMIN belongs to this network
namespace; host routes/firewall do not change. A local default route enables
OUTPUT/NAT processing, while explicit OUTPUT filtering and internal Docker
networks prevent direct egress. The wrapper supervises both processes and
forwards termination to them.
`--proxy` in upstream Bot API controls outgoing webhooks, not MTProto.

The Russia overlay joins `telegram-net` (internal) and the existing internal
`vless-relay_vpn-ingress` network. Telegram TCP goes through the existing
password-protected `entry:10091` SOCKS endpoint and the established Reality
reverse tunnel to hostkey-finland. The endpoint allows only Telegram IPv4
ranges on TCP 443 and rejects everything else. It shares the existing Telemt
SOCKS transport credential: copy only `secrets/telemt/socks-password` from the
relay to this project's `secrets/socks-password` (0600). Update both copies
when rotating that transport credential. Do not copy other relay secrets.
There is no direct public route from the API container if the proxy fails.
The host itself, VPN devices, and other bots keep their existing routes.

Private `.env` on Russia selects
`COMPOSE_FILE=compose/docker-compose.yml:compose/compose.russia.yml` and holds
TELEGRAM_API_ID / TELEGRAM_API_HASH. Preserve the named volume
`telegram-bot-api-data`; other bots on Russia can join `telegram-net` and mount
that volume read-only when required for media. No API port is published on Russia; use the internal Docker network or image-compose exec for diagnostics.
The HTTP probe checks API liveness; verify a real bot's getMe/getUpdates
separately to confirm Telegram connectivity.

Versions live in `makefiles/versions.mk`; `make check image-check` validates
Compose, shell and release lifecycle. `make image-build` builds the proxy-enabled
API image in CI, and `make image-publish` publishes that exact artifact. Russia
workflow uses RUSSIA_VM_HOST, RUSSIA_VM_USER, RUSSIA_VM_SSH_KEY,
RUSSIA_VM_PROJECT_PATH and requires RUSSIA_DEPLOY_ENABLED=true for delivery.
`make ci-deploy` checks clean main/revision under a host lock and activates the
published digest with `--no-build --wait`. `make image-compose IMAGE_ARGS=ps`
inspects the active artifact. Legacy server delivery requires explicit
SERVER_DEPLOY_ENABLED=true; do not target Russia with the server secrets.
Existing server runtime and all its bots remain untouched by Russia delivery.

For moving a bot without dropping queued updates: stop its old polling process,
call deleteWebhook (without drop_pending_updates), then close on the old API.
Archive only this bot's private session directory, preserve ownership, restore
it into the new volume, then start polling against the new API. Never run two
copies of that session/token. This follows the
[upstream migration procedure](https://github.com/tdlib/telegram-bot-api#moving-a-bot-from-one-local-server-to-another).
Keep a private off-VM copy before activation. Do not print session paths, which
may contain the bot token. Rollback after new updates needs the latest closed
session and latest application database transferred back first.
