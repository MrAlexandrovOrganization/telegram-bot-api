ARG TELEGRAM_BOT_API_IMAGE
FROM ${TELEGRAM_BOT_API_IMAGE}
ARG PROXYCHAINS_VERSION
RUN apk add --no-cache "proxychains-ng=${PROXYCHAINS_VERSION}"
COPY scripts/proxy-entrypoint.sh /usr/local/bin/telegram-api-proxy
ENTRYPOINT ["/usr/local/bin/telegram-api-proxy"]
