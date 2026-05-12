#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# build.sh — Build and push the Parking app Docker image
#
# Prerequisites:
#   • Docker daemon running locally (or a remote DOCKER_HOST)
#   • Write access to the registry (docker login, see below)
#   • jq installed  (reads the version from CloudronManifest.json)
#
# Usage:
#   ./build.sh                  # build & push using version from manifest
#   ./build.sh --push           # same (explicit)
#   ./build.sh --no-push        # build only, do not push
#   ./build.sh --version 0.2.0  # override version tag (does not edit manifest)
#
# ── Registry ──────────────────────────────────────────────────────────────────
#
# Images are pushed to the private Korpit Docker registry:
#   https://docs.cloudron.io/packages/docker-registry
#
# To authenticate (one-time per machine):
#   docker login registry.korpit.net
#
# To configure a self-hosted registry with the Cloudron registry package, see:
#   https://docs.cloudron.io/packages/docker-registry
#
# ── Cloudron docker-builder (alternative) ────────────────────────────────────
#
# If you prefer to use the Cloudron build service instead of building locally:
#   https://docs.cloudron.io/packages/docker-builder
#
# The builder at https://build.korpit.net/ can be triggered via its UI or API.
# Point it at this Git repository; it will:
#   1. Clone the repo
#   2. Run `docker build`
#   3. Push the resulting image to registry.korpit.net automatically
#
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
REGISTRY="registry.korpit.net"
IMAGE_NAME="parking"
MANIFEST="CloudronManifest.json"

# ── Parse arguments ───────────────────────────────────────────────────────────
DO_PUSH=true
VERSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --push)       DO_PUSH=true ;;
        --no-push)    DO_PUSH=false ;;
        --version)    shift; VERSION_OVERRIDE="${1}" ;;
        *) echo "Unknown argument: ${1}"; exit 1 ;;
    esac
    shift
done

# ── Resolve version ───────────────────────────────────────────────────────────
if [ -n "${VERSION_OVERRIDE}" ]; then
    VERSION="${VERSION_OVERRIDE}"
else
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required to read the version from ${MANIFEST}."
        echo "Install it with: sudo apt-get install jq  OR  brew install jq"
        exit 1
    fi
    VERSION=$(jq -r '.version' "${MANIFEST}")
fi

if [ -z "${VERSION}" ] || [ "${VERSION}" = "null" ]; then
    echo "Error: could not determine version from ${MANIFEST}"
    exit 1
fi

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════╗"
echo "  Building: ${FULL_IMAGE}"
echo "╚══════════════════════════════════════════════╝"

docker build \
    --label "cloudron.app.id=net.korpit.parking" \
    --label "cloudron.app.version=${VERSION}" \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    .

echo ""
echo "Build successful: ${FULL_IMAGE}"

# ── Push ──────────────────────────────────────────────────────────────────────
if [ "${DO_PUSH}" = true ]; then
    echo ""
    echo "Pushing to ${REGISTRY}…"

    docker push "${FULL_IMAGE}"
    docker push "${LATEST_IMAGE}"

    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "  Pushed: ${FULL_IMAGE}"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "Next step — install on Cloudron:"
    echo "  cloudron install --image ${FULL_IMAGE}"
    echo ""
    echo "Or update an existing installation:"
    echo "  cloudron update --app <app-id> --image ${FULL_IMAGE}"
else
    echo ""
    echo "Image built locally (not pushed). To push manually:"
    echo "  docker push ${FULL_IMAGE}"
    echo "  docker push ${LATEST_IMAGE}"
fi
