ARG TELEGRAM_BOT_API_IMAGE
FROM ${TELEGRAM_BOT_API_IMAGE}
ARG REDSOCKS_VERSION
ARG IPTABLES_VERSION
RUN apk add --no-cache "redsocks=${REDSOCKS_VERSION}" "iptables=${IPTABLES_VERSION}"
COPY scripts/proxy-entrypoint.sh /usr/local/bin/telegram-api-proxy
ENTRYPOINT ["/usr/local/bin/telegram-api-proxy"]
