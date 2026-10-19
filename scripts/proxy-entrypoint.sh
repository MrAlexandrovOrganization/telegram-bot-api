#!/bin/sh
set -eu
# All rules and routes apply only to this container's network namespace.
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
base {
 log_debug = off;
 log_info = off;
 log = "stderr";
 daemon = off;
 redirector = iptables;
}
redsocks {
 local_ip = 127.0.0.1;
 local_port = 12345;
 ip = $proxy_ip;
 port = 10091;
 type = socks5;
 login = "telemt";
 password = "$password";
}
EOF
unset password
# Only Telegram TCP/443 is redirected. The upstream independently enforces
# the same destination allowlist. No direct egress for any other traffic.
iptables -N TELEGRAM_API_OUT 2>/dev/null || true
iptables -F TELEGRAM_API_OUT
iptables -A TELEGRAM_API_OUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A TELEGRAM_API_OUT -o lo -j ACCEPT
iptables -A TELEGRAM_API_OUT -d "$proxy_ip" -p tcp --dport 10091 -j ACCEPT
iptables -A TELEGRAM_API_OUT -j REJECT
iptables -C OUTPUT -j TELEGRAM_API_OUT 2>/dev/null || iptables -I OUTPUT 1 -j TELEGRAM_API_OUT
iptables -t nat -N TELEGRAM_API_NAT 2>/dev/null || true
iptables -t nat -F TELEGRAM_API_NAT
for cidr in 91.105.192.0/23 91.108.4.0/22 91.108.8.0/22 91.108.12.0/22 91.108.16.0/22 91.108.20.0/22 91.108.56.0/22 149.154.160.0/20 185.76.151.0/24; do
 iptables -t nat -A TELEGRAM_API_NAT -d "$cidr" -p tcp --dport 443 -j REDIRECT --to-ports 12345
done
iptables -t nat -C OUTPUT -j TELEGRAM_API_NAT 2>/dev/null || iptables -t nat -I OUTPUT 1 -j TELEGRAM_API_NAT
# A route permits kernel OUTPUT/NAT processing. Both Docker networks remain
# internal; filtering above and SOCKS are the only allowed outbound path.
ip route show | grep -q '^default ' || ip route add default dev eth0
redsocks -t -c "$config"
redsocks -c "$config" &
proxy_pid=$!
/docker-entrypoint.sh "$@" &
api_pid=$!
cleanup() {
 trap - TERM INT
 kill -TERM "$api_pid" "$proxy_pid" 2>/dev/null || true
 wait "$api_pid" 2>/dev/null || true
 wait "$proxy_pid" 2>/dev/null || true
 rm -f "$config"
}
trap 'cleanup; exit 0' TERM INT
set +e
wait -n
status=$?
cleanup
exit "$status"
