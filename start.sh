#!/bin/sh
# Invoice Ninja on Railway: start script for the official invoiceninja/invoiceninja-debian image.
# Railway volumes can't be shared between services, so instead of upstream's separate nginx
# container this adds Caddy (pinned, checksum-verified) next to PHP-FPM, the queue workers and the
# scheduler under the image's own supervisord. Then it hands over to the image's init.sh.
set -eu

# ---- Defaults (any of these can be overridden with a service variable) ----
export PORT="${PORT:-8080}"
export APP_ENV="${APP_ENV:-production}"
export APP_DEBUG="${APP_DEBUG:-false}"
export REQUIRE_HTTPS="${REQUIRE_HTTPS:-true}"
export TRUSTED_PROXIES="${TRUSTED_PROXIES:-*}"
export IS_DOCKER="${IS_DOCKER:-true}"
export PDF_GENERATOR="${PDF_GENERATOR:-snappdf}"
export FILESYSTEM_DISK="${FILESYSTEM_DISK:-debian_docker}"
export DB_CONNECTION="${DB_CONNECTION:-mysql}"
export QUEUE_CONNECTION="${QUEUE_CONNECTION:-database}"
export CACHE_DRIVER="${CACHE_DRIVER:-file}"
export SESSION_DRIVER="${SESSION_DRIVER:-file}"
export SCOUT_DRIVER="${SCOUT_DRIVER:-null}"
# Mail is optional: with no MAIL_HOST, mail goes to the log. Blank optional values are unset so
# Laravel's own defaults (port 587, tls) apply.
for v in MAIL_MAILER MAIL_HOST MAIL_PORT MAIL_USERNAME MAIL_PASSWORD MAIL_ENCRYPTION MAIL_SCHEME MAIL_FROM_ADDRESS MAIL_FROM_NAME; do
  eval "[ -n \"\${$v:-}\" ] || unset $v"
done
if [ -n "${MAIL_HOST:-}" ]; then export MAIL_MAILER="${MAIL_MAILER:-smtp}"; else export MAIL_MAILER="${MAIL_MAILER:-log}"; fi
export MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS:-${IN_USER_EMAIL:-}}"
export MAIL_FROM_NAME="${MAIL_FROM_NAME:-Invoice Ninja}"

# ---- Caddy web server (cached on the storage volume, verified on every boot) ----
CADDY_VERSION=2.11.9
CADDY_SHA512=0e85544340290a16ce4bfb76fe7d65e9de1bf3a6e67f5ccfff30b30d27ea4c73e078077b7bf3e58ae60b6b12e44327705287059c775bca5782e8ee85ea7edd75
CACHE_DIR=/var/www/html/storage/railway
TGZ="$CACHE_DIR/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
mkdir -p "$CACHE_DIR"
if ! echo "$CADDY_SHA512  $TGZ" | sha512sum -c - >/dev/null 2>&1; then
  echo "Downloading Caddy $CADDY_VERSION..."
  curl -fsSL --retry 5 --retry-delay 3 -o "$TGZ.tmp" \
    "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
  echo "$CADDY_SHA512  $TGZ.tmp" | sha512sum -c -
  mv "$TGZ.tmp" "$TGZ"
fi
tar -xzf "$TGZ" -C /usr/local/bin caddy
chmod 0755 /usr/local/bin/caddy

mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<'CADDY'
{
	admin off
	auto_https off
	persist_config off
	servers {
		trusted_proxies static 0.0.0.0/0 ::/0
	}
}

:{$PORT} {
	root * /var/www/html/public
	encode gzip
	request_body {
		max_size 50MB
	}
	header {
		X-Frame-Options SAMEORIGIN
		X-Content-Type-Options nosniff
		-Server
	}
	@hidden {
		path */.*
		not path /.well-known/*
	}
	respond @hidden 404
	php_fastcgi 127.0.0.1:9000
	file_server
}
CADDY

cat > /etc/supervisor/conf.d/caddy.conf <<'SUP'
[program:caddy]
command=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
autostart=true
autorestart=true
priority=10
user=www-data
environment=HOME="/tmp",XDG_DATA_HOME="/tmp/caddy-data",XDG_CONFIG_HOME="/tmp/caddy-config"
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
SUP

# ---- Wait for MySQL (init.sh runs migrations straight away) ----
echo "Waiting for MySQL at ${DB_HOST:-?}:${DB_PORT:-3306}..."
i=0
until php -r 'try { new PDO("mysql:host=".getenv("DB_HOST").";port=".(getenv("DB_PORT") ?: 3306).";dbname=".getenv("DB_DATABASE"), getenv("DB_USERNAME"), getenv("DB_PASSWORD"), [PDO::ATTR_TIMEOUT => 3]); } catch (Throwable $e) { fwrite(STDERR, $e->getMessage()."\n"); exit(1); }'; do
  i=$((i+1)); [ "$i" -ge 60 ] && { echo "MySQL not reachable, giving up"; exit 1; }
  sleep 3
done

exec /usr/local/bin/init.sh supervisord -c /etc/supervisor/supervisord.conf
