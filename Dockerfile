# ──────────────────────────────────────────────────────────────────────────────
# Parking — Cloudron domain parking app
#
# Cloudron base image reference:
#   https://docs.cloudron.io/packaging/tutorial#creating-the-image
#
# We use cloudron/base (Ubuntu LTS) which provides:
#   • Supervisord        – process supervision (used if we ever add more procs)
#   • Gosu               – privilege dropping to www-data
#   • Common build tools – curl, jq, python3, etc.
#   • /app/pkg/          – read-only mount for app files (where we COPY to)
#   • /app/data/         – persistent read-write storage (Cloudron mounts this)
#
# The image is intentionally minimal:
#   • Only nginx is added — no database, no runtime framework
#   • Pages are generated once at container startup as static HTML
#   • All customisation lives in /app/data/ (persists across updates/restarts)
# ──────────────────────────────────────────────────────────────────────────────

FROM cloudron/base:5.0.0

# ── Labels ────────────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="Parking" \
      org.opencontainers.image.description="Lightweight Cloudron domain parking app" \
      org.opencontainers.image.authors="Korpit <admin@korpit.net>" \
    org.opencontainers.image.version="0.2.4"

# ── System packages ───────────────────────────────────────────────────────────
# nginx   : static file server — the only runtime dependency
# jq      : JSON parsing used in generate-vhosts.sh to read domains.json
# python3 : safe string substitution in generate-vhosts.sh (avoids sed escaping issues)
#

# python3 is already present in cloudron/base; jq and nginx are added here.
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nginx \
        jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# ── Nginx baseline cleanup ────────────────────────────────────────────────────
# Remove Cloudron base / Ubuntu default nginx configs; we manage our own.
RUN rm -f /etc/nginx/sites-enabled/default \
          /etc/nginx/sites-available/default \
          /etc/nginx/conf.d/default.conf

# ── App files (read-only at runtime) ─────────────────────────────────────────
# Cloudron convention: app files live in /app/pkg/
# IMPORTANT: Never write to /app/pkg/ at runtime — it is read-only after build.
COPY app/ /app/pkg/

RUN chmod +x \
        /app/pkg/start.sh \
        /app/pkg/scripts/generate-vhosts.sh

# ── Runtime working directories ───────────────────────────────────────────────
# /tmp/parking/        – ephemeral; recreated on each container start
#   vhosts/            – generated nginx server-block .conf files
#   www/<domain>/      – generated per-domain index.html files
#
# /app/data/           – persistent; mounted by Cloudron; survives restarts/updates
#   images/            – optional per-domain logo images (PNG/JPG/SVG)
#   domains.json       – per-domain title / image / blurb overrides
#
# We pre-create /app/data/images here so it exists for local `docker run` testing.
# On a real Cloudron install Cloudron mounts /app/data before the CMD runs.
RUN mkdir -p /tmp/parking/vhosts \
             /tmp/parking/www \
             /tmp/parking/client_body \
             /tmp/parking/fastcgi_temp \
             /tmp/parking/proxy_temp \
             /tmp/parking/scgi_temp \
             /tmp/parking/uwsgi_temp \
             /app/data/images \
             /run/nginx && \
    chown -R www-data:www-data /tmp/parking /run/nginx

# ── Expose the HTTP port declared in CloudronManifest.json ───────────────────
EXPOSE 8000

# ── Entrypoint ────────────────────────────────────────────────────────────────
CMD ["/app/pkg/start.sh"]
