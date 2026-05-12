#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# start.sh — Container entrypoint for the Parking app
#
# Cloudron documentation:
#   Packaging tutorial: https://docs.cloudron.io/packaging/tutorial
#   Environment vars:   https://docs.cloudron.io/packaging/reference#environment
#
# ── What this script does ─────────────────────────────────────────────────────
#
#   1. Ensures /app/data/ has the expected layout (first-run bootstrap)
#   2. Reads Cloudron-provided environment variables to discover all domains
#      this app instance should serve
#   3. Calls generate-vhosts.sh to write per-domain nginx configs + HTML pages
#   4. Validates the generated nginx config
#   5. Starts nginx in the foreground (required by Cloudron — no daemon mode)
#
# ── Cloudron environment variables consumed ───────────────────────────────────
#
#   CLOUDRON_APP_DOMAIN   (string)   — always set; the app's primary domain.
#                                      Example: "parked.example.com"
#
#   CLOUDRON_APP_ALIASES  (string)   — space-separated list of secondary
#                                      (aliased) domains added via the Cloudron
#                                      admin under App → Domains → Add domain.
#                                      May be empty if no aliases are configured.
#                                      Example: "foo.com bar.net old-brand.io"
#
#   See: https://docs.cloudron.io/apps#secondary-domains
#
# ── Persistent data layout (/app/data/) ──────────────────────────────────────
#
#   /app/data/
#   ├── domains.json        ← per-domain customisation (auto-created on first run)
#   └── images/             ← optional per-domain logo images (PNG / JPG / SVG)
#       ├── parked.example.com.png   ← named after the exact domain
#       └── foo.com.svg
#
# ── Ephemeral runtime layout (/tmp/parking/) ─────────────────────────────────
#
#   Rebuilt from scratch on every container start.
#
#   /tmp/parking/
#   ├── vhosts/
#   │   ├── parked.example.com.conf  ← nginx server block per domain
#   │   ├── foo.com.conf
#   │   └── _catchall.conf           ← default_server fallback
#   └── www/
#       ├── parked.example.com/
#       │   └── index.html           ← rendered parking page
#       └── foo.com/
#           └── index.html
#
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
DATA_DIR="/app/data"
IMAGES_DIR="${DATA_DIR}/images"
CONFIG_FILE="${DATA_DIR}/domains.json"
PKG_DIR="/app/pkg"

# ── 1. Bootstrap persistent data directory ────────────────────────────────────
# /app/data is mounted by Cloudron before this script runs.
# On first install the directory is empty; we populate it with sensible defaults.

echo "[parking] Checking persistent data directory…"

mkdir -p "${IMAGES_DIR}"

# Copy default image to images directory so it can be served as a fallback
if cp "${PKG_DIR}/www/default/img/default.svg" "${IMAGES_DIR}/default.svg" 2>&1; then
    echo "[parking] ✓ Copied default image to ${IMAGES_DIR}/default.svg"
else
    echo "[parking] ✗ Warning: could not copy default image"
    ls -la "${IMAGES_DIR}/" || true
fi

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "[parking] First run — creating default ${CONFIG_FILE}"
    cat > "${CONFIG_FILE}" << 'DEFAULTCONFIG'
{
  "_readme": [
    "Parking app domain configuration.",
    "Edit this file to customise each parked domain, then restart the app.",
    "Keys in 'domains' must be exact domain names (case-sensitive).",
    "Any field set to null inherits from '_defaults'."
  ],

  "_defaults": {
    "title": null,
    "image": null,
    "blurb": "This domain is parked and will be available soon."
  },

  "domains": {
    "_example_com": {
      "_comment": "Rename this key to your actual domain, e.g. 'example.com'.",
      "title":  "Example Domain",
      "image":  null,
      "blurb":  "Check back soon — something great is coming."
    }
  }
}
DEFAULTCONFIG
    echo "[parking] Created ${CONFIG_FILE} — edit it to customise each domain."
fi

# ── 2. Discover all domains to serve ──────────────────────────────────────────
# Cloudron always sets CLOUDRON_APP_DOMAIN.
# CLOUDRON_ALIAS_DOMAINS is a comma-separated list of additional domains added via
# the admin under App → Location (secondary domains / aliases).
# Note: Older Cloudron versions used CLOUDRON_APP_ALIASES (space-separated).
# Ref: https://docs.cloudron.io/apps#secondary-domains

PRIMARY_DOMAIN="${CLOUDRON_APP_DOMAIN:-localhost}"

# Try both variable names for compatibility with different Cloudron versions
ALIASES="${CLOUDRON_ALIAS_DOMAINS:-}"
if [ -z "${ALIASES}" ]; then
    ALIASES="${CLOUDRON_APP_ALIASES:-}"
fi

# Convert comma-separated to space-separated for internal use
ALIASES=$(echo "${ALIASES}" | tr ',' ' ')

ALL_DOMAINS="${PRIMARY_DOMAIN}"
if [ -n "${ALIASES}" ]; then
    ALL_DOMAINS="${ALL_DOMAINS} ${ALIASES}"
fi

# Add domains from domains.json
if [ -f "${CONFIG_FILE}" ]; then
    echo "[parking] Reading additional domains from domains.json…"
    JSON_DOMAINS=$(jq -r '.domains | keys[]' "${CONFIG_FILE}" 2>/dev/null | grep -v '^_' | tr '\n' ' ' || true)
    if [ -n "${JSON_DOMAINS}" ]; then
        echo "[parking] Found in JSON: ${JSON_DOMAINS}"
        # Add JSON domains to ALL_DOMAINS (deduplicating automatically in the loop)
        for domain in ${JSON_DOMAINS}; do
            if ! echo " ${ALL_DOMAINS} " | grep -q " ${domain} "; then
                ALL_DOMAINS="${ALL_DOMAINS} ${domain}"
            fi
        done
    fi
fi

echo "[parking] Primary domain : ${PRIMARY_DOMAIN}"
echo "[parking] Aliases        : ${ALIASES:-<none>}"
echo "[parking] All domains    : ${ALL_DOMAINS}"

# ── 3. Generate nginx vhosts and HTML pages ────────────────────────────────────
echo "[parking] Generating vhosts and parking pages…"

"${PKG_DIR}/scripts/generate-vhosts.sh" \
    "${ALL_DOMAINS}" \
    "${CONFIG_FILE}" \
    "${IMAGES_DIR}"

# ── 4. Install nginx base config ──────────────────────────────────────────────
# Copy to /tmp/parking/ (writable) instead of /etc/nginx/ (read-only in Cloudron)
NGINX_CONF="/tmp/parking/nginx.conf"
cp "${PKG_DIR}/nginx/nginx.conf" "${NGINX_CONF}"

# Create nginx temp directories and runtime directory (needed for Cloudron's read-only mounts)
mkdir -p /tmp/parking/{client_body,fastcgi_temp,proxy_temp,scgi_temp,uwsgi_temp}
mkdir -p /run/nginx

# ── 5. Validate ───────────────────────────────────────────────────────────────
echo "[parking] Validating nginx configuration…"
nginx -t -c "${NGINX_CONF}"

# ── 6. Start nginx ────────────────────────────────────────────────────────────
# Cloudron requires the process to run in the foreground.
# exec replaces this shell process with nginx — cleaner signal handling.
echo "[parking] Starting nginx on port 8000…"
exec nginx -g "daemon off;" -c "${NGINX_CONF}"
