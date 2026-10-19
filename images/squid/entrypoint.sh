#!/bin/sh
# Entrypoint for the sandbox allowlisting squid (spec 20, Unit 3).
#
# Squid drops privileges to the unprivileged `proxy` user, which cannot reopen
# the container's root-owned stdout/stderr pipes, so it logs to files and this
# script forwards them to the container streams (the same approach as the
# upstream `ubuntu/squid` image).
set -eu

LOG_DIR=/var/log/squid
SSL_DB=/var/spool/squid/ssl_db

mkdir -p "$LOG_DIR" /var/spool/squid
touch "$LOG_DIR/access.log" "$LOG_DIR/cache.log"

# The ssl-bump port spawns squid's certificate helper, which needs an initialised
# certificate database even though the proxy only peeks at the SNI and splices
# (it never mints a certificate). Recreate it on every start.
rm -rf "$SSL_DB"
/usr/lib/squid/security_file_certgen -c -s "$SSL_DB" -M 4MB >/dev/null

chown -R proxy:proxy "$LOG_DIR" /var/spool/squid 2>/dev/null || true

tail -n 0 -F "$LOG_DIR/access.log" &
tail -n 0 -F "$LOG_DIR/cache.log" >&2 &

# `-z` builds the cache/swap trees, then exits; idempotent and safe on every start.
/usr/sbin/squid -Nz -f /etc/squid/squid.conf >/dev/null 2>&1 || true

exec /usr/sbin/squid "$@"
