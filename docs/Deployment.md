# Deployment Guide

This guide covers setting up the infrastructure, building, and deploying the Parking app to Cloudron.

---

## Quick start

```bash
# Make changes, then:
git commit -am "Update parking page"
git push origin main

# Build and optionally deploy
./cloudron-build.sh

# When ready to publish to community:
./cloudron-publish.sh
```

---

## Deployment configuration

Create or edit `deployment.config` to customize your deployment:

```bash
# Docker registry URL where images are pushed
REGISTRY_IMAGE_BASE="registry.korpit.net/parking"

# Optional: default app location for one-click deployment
# Leave empty to prompt during build
DEFAULT_APP_LOCATION="parking.example.com"
```

The scripts use these settings to determine where to push images and where to deploy.

---

## One-time infrastructure setup

This section covers a **one-time** setup of the Docker registry and Cloudron builder.

### 1. Install the Docker Registry

The Docker Registry app provides a private Docker Registry v2 instance where
all built images are stored.

**Install via Cloudron admin:**

1. Open your Cloudron admin panel → **App Store**.
2. Search for **Docker Registry** and install it at your chosen domain (e.g., `registry.korpit.net`).
3. Once running, open the app's **Settings** tab and create at least one user:
   - **Username** — e.g., `builder` (used by the build service to push images)
   - **Password** — generate a strong password and save it somewhere safe
   - Add a second user for local developer access if needed (or reuse the same one)

**Authenticate your local machine:**

```bash
docker login registry.korpit.net
# Enter the username and password you created above
```

Your credentials are stored in `~/.docker/config.json`. Repeat this on every machine that will run builds.

**Verify the registry is working:**

```bash
docker pull alpine:latest
docker tag  alpine:latest registry.korpit.net/test:latest
docker push registry.korpit.net/test:latest
docker rmi  registry.korpit.net/test:latest
echo "Registry OK"
```

### 2. Install the Docker Builder

The Docker Builder watches a Git repository and automatically builds and pushes Docker images.

**Install via Cloudron admin:**

1. Open your Cloudron admin panel → **App Store**.
2. Search for **Docker Builder** and install it at your chosen domain (e.g., `parking.korpit.xyz`).
3. Open the builder's web UI and log in.

**Configure the Cloudron CLI:**

1. In the builder's web UI, copy the **build token**.
2. Run the login command:

   ```bash
   cloudron build login --url 'https://parking.korpit.xyz' --build-token <your-build-token>
   ```

3. Configure the repository to push to your registry:

   ```bash
   cd /path/to/parking/repo
   cloudron build --repository registry.korpit.net/parking --tag init-check
   ```

   This stores the repository for future builds in this project.

**Test the build:**

```bash
cloudron build --tag test-build
```

### 3. Allow Cloudron to pull from the private registry

When running `cloudron install` or `cloudron update`, Cloudron needs credentials to pull from your registry.

```bash
# Tell the Cloudron CLI about your private registry (one-time)
cloudron registry add \
  --registry registry.korpit.net \
  --username <username> \
  --password <password>
```

> Alternatively, add credentials in the Cloudron admin under **Settings → Docker Registries**.

---

## Building the image

### Option 1: Cloudron Build Service (recommended)

The build service automatically builds in a clean environment and pushes to your registry.

**Prerequisite:** Complete the infrastructure setup above.

**Build and push:**

```bash
# Using cloudron-build.sh (recommended)
./cloudron-build.sh

# Or manually with the cloudron CLI
cloudron build --tag 0.2.1
```

**Advantages:**
- Clean build environment every time
- No local Docker required
- Consistent builds across developers
- Build logs accessible via `cloudron build logs`

### Option 2: Local build with build.sh

Use this for quick iteration without pushing to the build service.

**Prerequisite:** Authenticate with your private registry

```bash
docker login registry.korpit.net
```

**Build and push:**

```bash
# Build and push (reads version from CloudronManifest.json)
./build.sh

# Build only, without pushing
./build.sh --no-push

# Override the version tag
./build.sh --version 0.2.0
```

**Advantages:**
- Faster iteration
- Works offline
- Uses Docker cache

---

## Deployment workflow

### First installation

If the app is not yet installed on your Cloudron:

```bash
# 1. Build the image
./cloudron-build.sh

# When prompted, provide:
# - Subdomain (e.g., 'parking')
# - Domain (e.g., 'example.com')

# The script will run:
# cloudron install --app-id parking.example.com dev.bluepants.parked
```

Or manually:

```bash
# Build first
cloudron build --tag 0.1.0

# Then install
cloudron install --app-id parking.example.com dev.bluepants.parked
```

### Updating an existing installation

After building a new image:

```bash
# If your app is already installed, cloudron-build.sh will detect it
./cloudron-build.sh

# When prompted, choose to deploy to the existing installation
```

Or manually:

```bash
cloudron update --app parking.example.com \
  --image registry.korpit.net/parking:0.2.1
```

---

## Publishing to the community

When you're ready to publish a version for community use:

```bash
# 1. Make sure the version is built and tagged
./cloudron-build.sh

# 2. Publish the version to CloudronVersions.json
./cloudron-publish.sh

# The script will add the version to CloudronVersions.json

# 3. Commit the changes
git add CloudronVersions.json
git commit -m "Publish version 0.2.1"
git push

# 4. Host CloudronVersions.json at a public URL
# Users can add it in their Cloudron dashboard under Community apps
```

**URL format for users:**
```
https://your-domain/path/to/CloudronVersions.json
```

Users can then:
- Add the URL in their Cloudron dashboard under **Community apps**
- Or install directly with: `cloudron install --versions-url https://...`

---

## Releasing a new version

### 1. Increment version

Edit `app/version.txt` with the new semantic version (e.g., `0.2.1`):

```bash
echo "0.2.1" > app/version.txt
```

### 2. Build and deploy

```bash
./cloudron-build.sh
```

This automatically:
- Detects version in `app/version.txt`
- Suggests next version (e.g., 0.2.1 → 0.2.2)
- Updates `CloudronManifest.json` and `Dockerfile`
- Builds the image with the new tag
- Asks if you want to deploy

### 3. Publish when ready

```bash
./cloudron-publish.sh
```

This adds the version to `CloudronVersions.json` for distribution.

---

## Automation scripts

### cloudron-build.sh

Wrapper for building with automatic version management:

**Features:**
- Checks version consistency across files
- Auto-increments patch version (N.N.N format)
- Updates `CloudronManifest.json`, `app/version.txt`, `Dockerfile`
- Builds the image
- Detects existing installations and offers to deploy
- Offers to install on first run

**Usage:**
```bash
./cloudron-build.sh
```

**Configuration:**
Edit `deployment.config` to set `REGISTRY_IMAGE_BASE` and `DEFAULT_APP_LOCATION`.

### cloudron-publish.sh

Wrapper for publishing to the community registry:

**Features:**
- Adds version to `CloudronVersions.json`
- Handles updating existing versions
- Provides distribution instructions

**Usage:**
```bash
./cloudron-publish.sh
```

---

## Troubleshooting

### Build service fails

1. Verify the build token is valid:
   ```bash
   cloudron build login --url 'https://parking.korpit.xyz' --build-token <token>
   ```

2. Check build service logs:
   ```bash
   cloudron build logs
   ```

### Cloudron can't pull the image

- Verify credentials are configured in Cloudron admin: **Settings → Docker Registries**
- Or re-run: `cloudron registry add --registry registry.korpit.net --username <user> --password <pass>`

### Image tag mismatch

The build service may push to a default tag. Verify the tag in `deployment.config`:

```bash
REGISTRY_IMAGE_BASE="registry.korpit.net/parking"
```

And explicitly tag your build:

```bash
cloudron build --tag 0.2.1
```

### Local build authentication failed

Re-login to the registry:

```bash
docker login registry.korpit.net
```

---

## See also

- [Cloudron packaging docs](https://docs.cloudron.io/packaging/)
- [CloudronManifest.json reference](https://docs.cloudron.io/packaging/manifest)
- [Secondary domains](https://docs.cloudron.io/apps#secondary-domains)
- [Environment variables](https://docs.cloudron.io/packaging/reference#environment)
