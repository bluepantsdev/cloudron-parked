#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# generate-vhosts.sh — Generate per-domain nginx configs and parking HTML pages
#
# Called by start.sh at container startup.
#
# Usage:
#   generate-vhosts.sh "<space-separated domains>" <domains.json> <images-dir>
#
# Example:
#   generate-vhosts.sh "foo.com bar.net" /app/data/domains.json /app/data/images
#
# Reads app version from /app/pkg/version.txt (created during Docker build)
#
# For each domain the script:
#   1. Reads per-domain overrides from domains.json (using jq)
#   2. Falls back to _defaults for any missing/null field
#   3. Falls back to hard-coded defaults if _defaults is also absent
#   4. Resolves the image path: domain-named file → bundled default
#   5. Renders /app/pkg/www/template.html into /tmp/parking/www/<domain>/index.html
#   6. Renders /app/pkg/nginx/vhost.template into /tmp/parking/vhosts/<domain>.conf
#   7. Writes a catch-all _catchall.conf that returns the primary domain's page
#      for any Host header not explicitly matched by the other server blocks
#
# Token replacement uses Python 3's str.replace() — safe for values that contain
# slashes, ampersands, or other characters that would break sed.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
DOMAINS_STR="${1:?generate-vhosts.sh: missing domain list argument}"
CONFIG_FILE="${2:-/app/data/domains.json}"
IMAGES_DIR="${3:-/app/data/images}"

# ── Read version from file ───────────────────────────────────────────────────
VERSION_FILE="/app/pkg/version.txt"
if [ -f "${VERSION_FILE}" ]; then
    APP_VERSION=$(tr -d '\n' < "${VERSION_FILE}")
else
    APP_VERSION="unknown"
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
PKG_DIR="/app/pkg"
VHOSTS_DIR="/tmp/parking/vhosts"
WWW_DIR="/tmp/parking/www"

VHOST_TEMPLATE="${PKG_DIR}/nginx/vhost.template"
HTML_TEMPLATE="${PKG_DIR}/www/template.html"
DEFAULT_IMAGE_PATH="/app/pkg/www/default/img/default.svg"

mkdir -p "${VHOSTS_DIR}" "${WWW_DIR}"

# ── Helper: read a value from domains.json with layered fallback ──────────────
#
#   Resolution order for each field:
#     1. domains.<domain>.<field>   (domain-specific override)
#     2. _defaults.<field>          (site-wide default in the JSON)
#     3. $hard_default              (built-in fallback in this script)
#
get_config() {
    local domain="${1}"
    local field="${2}"
    local hard_default="${3}"

    local value

    # 1) Domain-specific override
    value=$(jq -r \
        --arg d "${domain}" \
        --arg f "${field}" \
        '.domains[$d][$f] // empty' \
        "${CONFIG_FILE}" 2>/dev/null || true)

    # 2) Site-wide _defaults
    if [ -z "${value}" ] || [ "${value}" = "null" ]; then
        value=$(jq -r \
            --arg f "${field}" \
            '._defaults[$f] // empty' \
            "${CONFIG_FILE}" 2>/dev/null || true)
    fi

    # 3) Hard-coded fallback
    if [ -z "${value}" ] || [ "${value}" = "null" ]; then
        value="${hard_default}"
    fi

    printf '%s' "${value}"
}

# ── Helper: safe token substitution via Python 3 ─────────────────────────────
#
# Python str.replace() handles arbitrary string values (slashes, quotes, etc.)
# without the escaping pitfalls of sed.
#
render_template() {
    local template_file="${1}"
    local domain="${2}"
    local title="${3}"
    local image="${4}"
    local blurb="${5}"
    local version="${6}"

    python3 - "${template_file}" "${domain}" "${title}" "${image}" "${blurb}" "${version}" << 'PYEOF'
import sys

template_path, domain, title, image, blurb, version = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

with open(template_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('__DOMAIN__', domain)
content = content.replace('__TITLE__',  title)
content = content.replace('__IMAGE__',  image)
content = content.replace('__BLURB__',  blurb)
content = content.replace('__VERSION__', version)

sys.stdout.write(content)
PYEOF
}

# ── Process each domain ───────────────────────────────────────────────────────
# Track the first (primary) domain for the catch-all block
PRIMARY_DOMAIN=""

for DOMAIN in ${DOMAINS_STR}; do
    echo "[parking] Configuring: ${DOMAIN}"

    # Set primary domain on first iteration
    if [ -z "${PRIMARY_DOMAIN}" ]; then
        PRIMARY_DOMAIN="${DOMAIN}"
    fi

    # ── Resolve: title ─────────────────────────────────────────────────────
    TITLE=$(get_config "${DOMAIN}" "title" "")
    if [ -z "${TITLE}" ] || [ "${TITLE}" = "null" ]; then
        TITLE="${DOMAIN}"   # domain name is the ultimate fallback title
    fi

    # ── Resolve: image src ─────────────────────────────────────────────────
    #
    # Priority:
    #   a) Explicit path in domains.json (e.g. an external URL or /img/custom.png)
    #   b) Auto-detected domain-named file in /app/data/images/
    #        e.g. /app/data/images/foo.com.png  → served via nginx as /img/foo.com.png
    #   c) Bundled default SVG (/img/default.svg via nginx alias)
    #
    IMAGE=$(get_config "${DOMAIN}" "image" "")

    if [ -z "${IMAGE}" ] || [ "${IMAGE}" = "null" ]; then
        if   [ -f "${IMAGES_DIR}/${DOMAIN}.png" ]; then
            IMAGE="/img/${DOMAIN}.png"
        elif [ -f "${IMAGES_DIR}/${DOMAIN}.jpg" ]; then
            IMAGE="/img/${DOMAIN}.jpg"
        elif [ -f "${IMAGES_DIR}/${DOMAIN}.jpeg" ]; then
            IMAGE="/img/${DOMAIN}.jpeg"
        elif [ -f "${IMAGES_DIR}/${DOMAIN}.svg" ]; then
            IMAGE="/img/${DOMAIN}.svg"
        elif [ -f "${IMAGES_DIR}/${DOMAIN}.webp" ]; then
            IMAGE="/img/${DOMAIN}.webp"
        else
            # nginx's try_files in the /img/ location handles the real fallback;
            # we reference the default here so the <img> src is always valid.
            IMAGE="/img/default.svg"
        fi
    fi

    # ── Resolve: blurb ─────────────────────────────────────────────────────
    BLURB=$(get_config "${DOMAIN}" "blurb" \
        "This domain is parked and will be available soon.")

    echo "[parking]   title : ${TITLE}"
    echo "[parking]   image : ${IMAGE}"
    echo "[parking]   blurb : ${BLURB:0:60}…"

    # ── Write nginx vhost ──────────────────────────────────────────────────
    VHOST_FILE="${VHOSTS_DIR}/${DOMAIN}.conf"
    render_template "${VHOST_TEMPLATE}" \
        "${DOMAIN}" "${TITLE}" "${IMAGE}" "${BLURB}" "${APP_VERSION}" \
        > "${VHOST_FILE}"
    echo "[parking]   → ${VHOST_FILE}"

    # ── Write rendered HTML ────────────────────────────────────────────────
    DOMAIN_WWW="${WWW_DIR}/${DOMAIN}"
    mkdir -p "${DOMAIN_WWW}"
    HTML_FILE="${DOMAIN_WWW}/index.html"
    render_template "${HTML_TEMPLATE}" \
        "${DOMAIN}" "${TITLE}" "${IMAGE}" "${BLURB}" "${APP_VERSION}" \
        > "${HTML_FILE}"
    echo "[parking]   → ${HTML_FILE}"

done

# ── Write catch-all server block ──────────────────────────────────────────────
#
# This block handles ANY domain that points to this app, even if not pre-configured
# in Cloudron's CLOUDRON_APP_ALIASES. It dynamically serves the correct page based
# on the incoming Host header.
#
echo "[parking] Writing dynamic catch-all vhost"

cat > "${VHOSTS_DIR}/_catchall.conf" << 'CATCHALL'
# ── Dynamic catch-all server block ───────────────────────────────────────────
# Serves domain-specific pages based on the Host header for any domain pointing
# to this app, whether or not it's pre-configured in Cloudron.
#
# Resolution order:
#   1. Try /tmp/parking/www/<host>/index.html (pre-generated for known domains)
#   2. Generate page on-the-fly using onthefly.html if domain is in domains.json
#   3. Fall back to primary domain's page
server {
    listen      8000 default_server;
    server_name _;

    # Use the Host header to determine which domain's page to serve
    set $domain_dir /tmp/parking/www/$host;
    
    root  /tmp/parking/www;
    index index.html;

    location = / {
        # Try to serve from domain-specific directory first
        try_files $domain_dir/index.html /onthefly.html =404;
    }

    location = /onthefly.html {
        internal;
        root /app/pkg/www;
        add_header Content-Type "text/html; charset=utf-8";
    }

    # VHost configuration viewer
    location = /vhosts {
        alias /app/pkg/www/vhosts.html;
        default_type "text/html; charset=utf-8";
    }

    # VHost configuration JSON
    location = /vhosts.json {
        alias /app/data/domains.json;
        default_type "application/json; charset=utf-8";
    }

    # Redirect all other paths to root
    location / {
        return 301 $scheme://$host/;
    }

    location /img/ {
        alias /app/data/images/;
        expires    30d;
        add_header Cache-Control "public, immutable";
    }

    location = /favicon.ico {
        alias /app/pkg/www/default/img/default.svg;
        expires 7d;
        log_not_found off;
    }

    add_header X-Frame-Options        "SAMEORIGIN"  always;
    add_header X-Content-Type-Options "nosniff"     always;
    add_header Referrer-Policy        "no-referrer" always;
}
CATCHALL

echo "[parking] Vhost generation complete ($(echo "${DOMAINS_STR}" | wc -w) domain(s) + dynamic catch-all)."
