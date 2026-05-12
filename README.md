# Parking — Cloudron Domain Parking App

A lightweight Cloudron app that displays a branded landing page for every domain
parked on your Cloudron instance. Uses nginx for static file serving (no database,
no runtime framework) and supports **multiple domains via Cloudron secondary domains**.

---

## Overview

| What it does | How it works |
|---|---|
| Serves a customisable parking page per domain | nginx static files, generated at startup |
| Handles multiple domains from one install | Cloudron secondary domains + per-domain nginx `server {}` blocks |
| Lets you customise title, image & blurb per domain | `/app/data/domains.json` (persists across restarts/updates) |
| Supports per-domain logo images | Place `<domain>.(png\|jpg\|svg)` in `/app/data/images/` |
| View vhost configuration | Visit `<domain>/vhosts` to see domains.json config (any domain) |
| Auto-redirect to root | All paths except `/`, `/vhosts`, `/vhosts.json`, `/img/*`, and `/favicon.ico` redirect to root |
| Minimal memory footprint | Pure static nginx, no PHP/Node/Python at runtime |

---

## Infrastructure

| Resource | URL | Cloudron package docs |
|---|---|---|
| Docker builder | https://parking.korpit.xyz/ | https://docs.cloudron.io/packages/docker-builder |
| Docker registry | https://registry.korpit.net/ | https://docs.cloudron.io/packages/docker-registry |
| Cloudron packaging tutorial | — | https://docs.cloudron.io/packaging/tutorial |
| Cloudron secondary domains | — | https://docs.cloudron.io/apps#secondary-domains |

---

## Deployment

See [docs/Deployment.md](docs/Deployment.md) for comprehensive deployment instructions:

- **One-time setup** — Docker registry and builder configuration
- **Building images** — Cloudron Build Service vs local build
- **Deploying** — First install and updates
- **Publishing** — Releasing to the community
- **Automation scripts** — `cloudron-build.sh` and `cloudron-publish.sh`
- **Configuration** — `deployment.config`

---

## Normal development workflow

After [one-time infrastructure setup](#deployment):

```bash
# Make changes, then:
git commit -am "Update parking page"
git push origin main

# Build via build service with version management
./cloudron-build.sh

# When ready to publish to community:
./cloudron-publish.sh
```

---

## Repository layout

```
.                                  ← git repo root
├── CloudronManifest.json          # Cloudron app manifest
├── CloudronVersions.json          # Version history for Cloudron app store
├── DESCRIPTION.md                 # App description for manifest
├── deployment.config              # Deployment configuration (registry, locations)
├── Dockerfile                     # Docker image definition
├── VersionHistory.md              # Version changelog
├── build.sh                       # Local build & push helper
├── cloudron-build.sh              # Cloudron build service wrapper
├── cloudron-publish.sh            # Publish to community registry wrapper
├── domains.json.example           # Annotated config reference
├── .gitignore
├── .dockerignore
├── README.md                      # ← you are here
├── docs/
│   └── Deployment.md              # Deployment guide (infrastructure, building, publishing)
└── app/                           # Copied to /app/pkg/ in the container (read-only)
    ├── start.sh                   # Container entrypoint
    ├── version.txt                # App version (authoritative)
    ├── nginx/
    │   ├── nginx.conf             # Base nginx config (low-memory tuned)
    │   └── vhost.template         # Per-domain server block template
    ├── scripts/
    │   └── generate-vhosts.sh     # Generates vhosts + HTML at startup
    └── www/
        ├── template.html          # Parking page HTML template
        ├── vhosts.html            # VHost configuration viewer page
        └── default/
            └── img/
                └── default.svg    # Bundled fallback parking icon
```

### Runtime file layout (inside the container)

```
/app/pkg/          ← read-only; contents of app/ above
/app/data/         ← persistent; mounted by Cloudron; survives updates
  domains.json     ← per-domain config (auto-created on first run)
  images/          ← optional per-domain logo files
    example.com.png
    foo.net.svg
/tmp/parking/      ← ephemeral; rebuilt on every container start
  vhosts/
    example.com.conf
    foo.net.conf
    _catchall.conf
  www/
    example.com/
      index.html
    foo.net/
      index.html
```

---

## Adding parked domains (secondary domains)

Cloudron routes additional domains to the same app container through its
**secondary domains** (aliases) feature.

> Reference: https://docs.cloudron.io/apps#secondary-domains

1. Open the Cloudron admin panel.
2. Navigate to **Apps** → select the Parking app → **Domains**.
3. Click **Add domain** and enter the domain you want to park
   (e.g. `old-brand.net`).
4. Cloudron will update DNS / routing and inject the domain into the
   `CLOUDRON_APP_ALIASES` environment variable inside the container.
5. **Restart the app** — `start.sh` re-reads `CLOUDRON_APP_ALIASES` and
   regenerates the nginx vhosts for all domains including the new one.

```bash
cloudron restart --app <app-id-or-location>
```

### How secondary domains reach the app

When a request arrives for `old-brand.net`, Cloudron's front-end nginx proxy
forwards it to the Parking app container with the original `Host: old-brand.net`
header intact. The generated nginx server block for that domain matches on
`server_name old-brand.net` and serves the correct parking page.

```
Internet → Cloudron front-end nginx → container:8000
                                          ↓
                                   nginx server_name old-brand.net
                                          ↓
                                   /tmp/parking/www/old-brand.net/index.html
```

---

## Customising parked domains

All per-domain configuration lives in `/app/data/domains.json` which persists
across container restarts and app updates.

### Editing the config

```bash
# Via the Cloudron CLI
cloudron exec --app <app-id> -- vi /app/data/domains.json

# Or via the Cloudron file manager in the web admin
```

### Config structure

```jsonc
{
  "_defaults": {
    "title":  null,          // null = use the domain name as title
    "image":  null,          // null = auto-detect from /app/data/images/
    "blurb":  "This domain is parked and will be available soon."
  },

  "domains": {
    "example.com": {
      "title": "example.com",           // displayed in <h1> and <title>
      "image": null,                    // null = auto-detect or default icon
      "blurb": "Coming soon!"           // paragraph text below the title
    },

    "acquired-brand.io": {
      "title": "Acquired Brand",
      "image": "/img/acquired-brand.io.png",  // custom image (see below)
      "blurb": "This brand is now part of our family."
    }
  }
}
```

See `domains.json.example` for a fully annotated reference copy.

Field resolution for each domain, in order:

1. `domains.<domain>.<field>` — domain-specific override
2. `_defaults.<field>` — site-wide default
3. Built-in fallback (domain name for title, default SVG for image, stock blurb)

### Using custom images

There are three ways to specify images for parked domains:

#### 1. Auto-detection (recommended)

Place image files named after the exact domain in `/app/data/images/` and set `"image": null`:

```bash
# Copy an image into the persistent data directory
cloudron exec --app <app-id> -- bash -c \
  "cp /tmp/my-logo.png /app/data/images/example.com.png"

# Supported formats (auto-detected by name):
#   <domain>.png   <domain>.jpg   <domain>.jpeg
#   <domain>.svg   <domain>.webp
```

In `domains.json`:
```json
"example.com": {
  "title": "Example",
  "image": null,
  "blurb": "Coming soon!"
}
```

The app will automatically detect and serve the image at `/img/example.com.png`.

#### 2. Explicit web path

Reference the image using the `/img/` URL path:

```json
"example.com": {
  "title": "Example",
  "image": "/img/example.com.png",
  "blurb": "Coming soon!"
}
```

The image must still be in `/app/data/images/example.com.png` — the `/img/` path is the web-accessible location served by nginx.

#### 3. External URL

Use a full external URL (e.g., from a CDN):

```json
"example.com": {
  "title": "Example",
  "image": "https://cdn.example.com/logos/example.png",
  "blurb": "Coming soon!"
}
```

### Applying changes

After editing `domains.json` or adding images, restart the app:

```bash
cloudron restart --app <app-id>
```

---

## Environment variables

These are injected automatically by Cloudron — you do not set them yourself.

| Variable | Description |
|---|---|
| `CLOUDRON_APP_DOMAIN` | Primary domain of the app installation |
| `CLOUDRON_APP_ALIASES` | Space-separated list of secondary/aliased domains (may be empty) |

See the full reference at https://docs.cloudron.io/packaging/reference#environment.

---

## Logo (app icon)

The Cloudron admin panel displays `logo.png` from the manifest root as the app icon.

Requirements: **256 × 256 px PNG**, square, transparent background preferred.

The repository ships without a `logo.png`. Create one before installing:

```bash
# Convert the default SVG to a 256×256 PNG using ImageMagick
convert -background none -resize 256x256 \
  app/www/default/img/default.svg logo.png
```

---

## Template reference

### app/www/template.html tokens

| Token | Replaced with |
|---|---|
| `__DOMAIN__` | Raw domain name, e.g. `example.com` |
| `__TITLE__` | Display title (from `domains.json` or domain name) |
| `__IMAGE__` | Image `src` attribute value |
| `__BLURB__` | Blurb paragraph text |

### app/nginx/vhost.template tokens

| Token | Replaced with |
|---|---|
| `__DOMAIN__` | Domain name — used in `server_name` and document `root` path |

---

## Extending this template

This repository is designed as a reusable template for Cloudron app packaging.
Key patterns to carry forward:

- **`CloudronManifest.json`** — adjust `id`, `title`, `version`, `httpPort`,
  and `addons` for your app. Full reference at https://docs.cloudron.io/packaging/manifest.
- **`Dockerfile`** — uses `cloudron/base` (Ubuntu LTS). Add packages in the
  `apt-get install` block.
- **`app/start.sh`** — the entrypoint pattern (init data dir → configure →
  validate → exec foreground process) works for any Cloudron app.
- **`build.sh`** — the build/push helper is generic; only `REGISTRY` and
  `IMAGE_NAME` need changing.
- **Secondary domains** — the `CLOUDRON_APP_ALIASES` env var pattern applies to
  any app that must serve multiple domains from a single installation.

---

## Troubleshooting

### App shows the wrong page for a domain

1. Confirm the domain appears in `CLOUDRON_APP_ALIASES`:
   ```bash
   cloudron exec --app <id> -- printenv CLOUDRON_APP_ALIASES
   ```
2. Confirm a vhost was generated for it:
   ```bash
   cloudron exec --app <id> -- ls /tmp/parking/vhosts/
   cloudron exec --app <id> -- cat /tmp/parking/vhosts/<domain>.conf
   ```
3. Restart the app to force vhost regeneration.

### nginx fails to start

```bash
# Check the startup logs
cloudron logs --app <id>

# Validate the nginx config manually inside the container
cloudron exec --app <id> -- nginx -t
```

### Custom image not showing

- Confirm the file is named exactly `<domain>.(png|jpg|svg|webp)`.
- Confirm it is in `/app/data/images/` (not `/app/pkg/`).
- Restart the app after uploading.

### Cloudron can't pull the image during install/update

Add the credentials directly in the Cloudron admin under **Settings → Docker Registries** (exact menu name may vary by Cloudron version).

### Build service pushes to wrong registry

If `cloudron build` tries to push to Docker Hub instead of your private registry:

```bash
# Configure the repository location
cloudron build --set-repository registry.korpit.net/parking
```

This setting is saved for future builds in this project directory.

### Build service authentication failed

Re-login to the build service:

```bash
cloudron build login \
  --url 'https://parking.korpit.xyz' \
  --build-token <your-build-token>
```

Get your build token from the build service web UI at https://parking.korpit.xyz/

---

## Licence

MIT — use as you see fit.
