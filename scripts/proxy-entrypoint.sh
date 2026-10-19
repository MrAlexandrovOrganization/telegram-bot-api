#!/bin/sh
set -eu
# SOCKS credentials are a mounted file, never a command argument or env value.
secret=/run/secrets/telegram-socks-password
[ -r "$secret" ] || { echo "SOCKS credential unavailable" >&2; exit 1; }
password=$(cat "$secret")
[ "${#password}" -eq 64 ] || { echo "Invalid SOCKS credential" >&2; exit 1; }
case "$password" in *[!0-9a-f]*) echo "Invalid SOCKS credential" >&2; exit 1 ;; esac
proxy_ip=$(getent hosts entry | awk 'NR == 1 {print $1}')
case "$proxy_ip" in ''|*[!0-9.]*) echo "SOCKS endpoint unavailable" >&2; exit 1 ;; esac
umask 077
config=$(mktemp /tmp/telegram-proxy.XXXXXX)
cat > "$config" <<EOF
strict_chain
quiet_mode
proxy_dns
tcp_read_time_out 80000
tcp_connect_time_out 15000
localnet 127.0.0.0/255.0.0.0
[ProxyList]
socks5 $proxy_ip 10091 telemt $password
EOF
unset password
exec proxychains4 -q -f "$config" /docker-entrypoint.sh "$@"
