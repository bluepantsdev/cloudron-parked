#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# cloudron-build.sh — Wrapper for Cloudron build service with version management
#
# This script:
#   1. Checks version consistency across 3 files:
#      - CloudronManifest.json
#      - app/version.txt
#      - Dockerfile
#   2. Reports any version mismatches (version.txt is authoritative)
#   3. Prompts for new version (with auto-increment suggestion if format is N.N.N)
#   4. Automatically updates 3 version files (NOT CloudronVersions.json)
#   5. Executes: cloudron build --tag <version>
#   6. Optionally deploys to parked.korpit.xyz
#
# Note: CloudronVersions.json is a version history/changelog and should be
#       manually updated only when publishing to the Cloudron App Store.
#
# Usage:
#   ./cloudron-build.sh
#
# Prerequisites:
#   - cloudron CLI installed and authenticated
#   - jq installed (for JSON parsing)
#
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Color codes for output ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── File paths ────────────────────────────────────────────────────────────────
MANIFEST_FILE="CloudronManifest.json"
VERSION_FILE="app/version.txt"
DOCKERFILE="Dockerfile"
CONFIG_FILE="deployment.config"

# ── Functions ─────────────────────────────────────────────────────────────────

# Extract version from CloudronManifest.json
get_manifest_version() {
    jq -r '.version' "${MANIFEST_FILE}" 2>/dev/null || echo "ERROR"
}

# Extract version from app/version.txt
get_version_txt() {
    if [ -f "${VERSION_FILE}" ]; then
        tr -d '\n' < "${VERSION_FILE}"
    else
        echo "ERROR"
    fi
}

# Extract version from Dockerfile LABEL
get_dockerfile_version() {
    grep -oP 'org\.opencontainers\.image\.version="\K[^"]+' "${DOCKERFILE}" 2>/dev/null || echo "ERROR"
}

# Increment version (if format is N.N.N)
increment_version() {
    local version="$1"
    
    # Check if version matches N.N.N format
    if [[ "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        # Increment patch version
        patch=$((patch + 1))
        
        echo "${major}.${minor}.${patch}"
    else
        # Can't auto-increment non-standard version
        echo ""
    fi
}

# Load deployment configuration
load_deployment_config() {
    # Set defaults
    REGISTRY_IMAGE_BASE="registry.korpit.net/parking"
    DEFAULT_APP_LOCATION=""
    
    # Load from config file if it exists
    if [ -f "${CONFIG_FILE}" ]; then
        # Source the config file, but only read specific variables
        # Use a subshell to avoid polluting the environment
        (
            source "${CONFIG_FILE}"
            echo "REGISTRY_IMAGE_BASE=${REGISTRY_IMAGE_BASE}"
            echo "DEFAULT_APP_LOCATION=${DEFAULT_APP_LOCATION}"
        ) | while IFS='=' read -r key value; do
            case "$key" in
                REGISTRY_IMAGE_BASE) REGISTRY_IMAGE_BASE="$value" ;;
                DEFAULT_APP_LOCATION) DEFAULT_APP_LOCATION="$value" ;;
            esac
        done || true
    fi
}

# Find installed app by manifest title, return app ID (domain)
find_installed_app() {
    local manifest_title="$1"
    
    # Try to get list of apps and find one matching the title
    if ! command -v cloudron &> /dev/null; then
        return 1
    fi
    
    # Attempt to list apps using cloudron CLI
    # The output format may vary, so we try to parse installation info
    local app_id=$(cloudron list 2>/dev/null | grep -i "${manifest_title}" | head -1 | awk '{print $1}' 2>/dev/null || echo "")
    
    # If that didn't work, try getting from cloudron info (for the current machine)
    if [ -z "${app_id}" ]; then
        # cloudron list shows installed apps; try to match by app location/domain
        # For now, return empty to prompt user
        return 1
    fi
    
    echo "${app_id}"
    return 0
}

# ── Main script ───────────────────────────────────────────────────────────────

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Cloudron Build Wrapper - Version Manager              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if required commands are available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq first.${NC}"
    exit 1
fi

if ! command -v cloudron &> /dev/null; then
    echo -e "${RED}Error: cloudron CLI is not installed.${NC}"
    exit 1
fi

# Get app name from manifest (for reference in messages)
APP_TITLE=$(jq -r '.title' "${MANIFEST_FILE}" 2>/dev/null || echo "App")

# Load deployment configuration
load_deployment_config

# ── Step 1: Extract versions from all files ──────────────────────────────────
echo -e "${BLUE}Checking version consistency across files...${NC}"
echo

MANIFEST_VER=$(get_manifest_version)
VERSION_TXT=$(get_version_txt)
DOCKERFILE_VER=$(get_dockerfile_version)

# Display current versions
echo "  CloudronManifest.json     : ${MANIFEST_VER}"
echo "  app/version.txt           : ${VERSION_TXT} (authoritative)"
echo "  Dockerfile                : ${DOCKERFILE_VER}"
echo

# ── Step 2: Check for consistency ─────────────────────────────────────────────
VERSIONS_MATCH=true

if [ "${MANIFEST_VER}" = "ERROR" ] || [ "${VERSION_TXT}" = "ERROR" ] || \
   [ "${DOCKERFILE_VER}" = "ERROR" ]; then
    echo -e "${RED}✗ Error: Could not extract version from one or more files${NC}"
    VERSIONS_MATCH=false
elif [ "${MANIFEST_VER}" != "${VERSION_TXT}" ] || \
     [ "${DOCKERFILE_VER}" != "${VERSION_TXT}" ]; then
    echo -e "${YELLOW}⚠ Warning: Version mismatch detected!${NC}"
    echo -e "${YELLOW}  app/version.txt is considered authoritative: ${VERSION_TXT}${NC}"
    echo
    VERSIONS_MATCH=false
    
    # Show which files are out of sync
    if [ "${MANIFEST_VER}" != "${VERSION_TXT}" ]; then
        echo -e "${YELLOW}  → CloudronManifest.json needs update (${MANIFEST_VER} → ${VERSION_TXT})${NC}"
    fi
    if [ "${DOCKERFILE_VER}" != "${VERSION_TXT}" ]; then
        echo -e "${YELLOW}  → Dockerfile needs update (${DOCKERFILE_VER} → ${VERSION_TXT})${NC}"
    fi
    echo
else
    echo -e "${GREEN}✓ All version files are in sync: ${VERSION_TXT}${NC}"
    echo
fi

# ── Step 3: Prompt for new version ───────────────────────────────────────────
CURRENT_VERSION="${VERSION_TXT}"

# Calculate suggested next version
SUGGESTED_VERSION=$(increment_version "${CURRENT_VERSION}")

echo -e "${BLUE}Current version: ${CURRENT_VERSION}${NC}"

if [ -n "${SUGGESTED_VERSION}" ]; then
    echo -e "${GREEN}Suggested next version: ${SUGGESTED_VERSION}${NC}"
    echo
    read -p "Enter new version [${SUGGESTED_VERSION}]: " NEW_VERSION
    
    # Use suggested version if user just presses Enter
    if [ -z "${NEW_VERSION}" ]; then
        NEW_VERSION="${SUGGESTED_VERSION}"
    fi
else
    echo -e "${YELLOW}(Version format is not N.N.N, cannot auto-suggest increment)${NC}"
    echo
    read -p "Enter new version: " NEW_VERSION
fi

# Validate that new version was provided
if [ -z "${NEW_VERSION}" ]; then
    echo -e "${RED}Error: No version provided. Exiting.${NC}"
    exit 1
fi

# Trim whitespace
NEW_VERSION=$(echo "${NEW_VERSION}" | xargs)

echo
echo -e "${GREEN}Updating version to: ${NEW_VERSION}${NC}"
echo

# ── Step 4: Update version in all files ──────────────────────────────────────
echo -e "${BLUE}Updating version files...${NC}"

# 4a. Update CloudronManifest.json
if jq --arg ver "${NEW_VERSION}" '.version = $ver' "${MANIFEST_FILE}" > "${MANIFEST_FILE}.tmp"; then
    mv "${MANIFEST_FILE}.tmp" "${MANIFEST_FILE}"
    echo "  ✓ Updated ${MANIFEST_FILE}"
else
    echo -e "${RED}  ✗ Failed to update ${MANIFEST_FILE}${NC}"
    rm -f "${MANIFEST_FILE}.tmp"
    exit 1
fi

# 4b. Update app/version.txt
if echo "${NEW_VERSION}" > "${VERSION_FILE}"; then
    echo "  ✓ Updated ${VERSION_FILE}"
else
    echo -e "${RED}  ✗ Failed to update ${VERSION_FILE}${NC}"
    exit 1
fi

# 4c. Update Dockerfile
if sed -i "s/org\.opencontainers\.image\.version=\"[^\"]*\"/org.opencontainers.image.version=\"${NEW_VERSION}\"/" "${DOCKERFILE}"; then
    echo "  ✓ Updated ${DOCKERFILE}"
else
    echo -e "${RED}  ✗ Failed to update ${DOCKERFILE}${NC}"
    exit 1
fi

echo
echo -e "${GREEN}Version files updated successfully!${NC}"
echo
echo -e "${YELLOW}Note: CloudronVersions.json is not auto-updated.${NC}"
echo -e "${YELLOW}      Update it manually when publishing to the app store.${NC}"
echo

# ── Step 5: Execute cloudron build ───────────────────────────────────────────
echo -e "${BLUE}Running: cloudron build --tag ${NEW_VERSION}${NC}"
echo

if cloudron build --tag "${NEW_VERSION}"; then
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Build Successful                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # ── Step 6: Check for installed apps and handle deployment ───────────────────
    echo -e "${BLUE}Checking for installed instances of ${APP_TITLE}...${NC}"
    echo
    
    # Try to find an existing installation
    INSTALLED_APP_ID=$(find_installed_app "${APP_TITLE}")
    FOUND_APP=$?
    
    if [ ${FOUND_APP} -eq 0 ] && [ -n "${INSTALLED_APP_ID}" ]; then
        # App is already installed
        echo -e "${GREEN}✓ Found existing installation: ${INSTALLED_APP_ID}${NC}"
        echo
        read -p "Deploy version ${NEW_VERSION} to ${INSTALLED_APP_ID}? [y/N]: " DEPLOY_NOW
        
        if [[ "${DEPLOY_NOW}" =~ ^[Yy]$ ]]; then
            # Get registry info from deployment config
            APP_ID=$(jq -r '.id' "${MANIFEST_FILE}")
            REGISTRY_IMAGE="${REGISTRY_IMAGE_BASE}:${NEW_VERSION}"
            
            echo
            echo -e "${BLUE}Deploying version ${NEW_VERSION} to ${INSTALLED_APP_ID}...${NC}"
            echo
            
            if cloudron update --app "${INSTALLED_APP_ID}" --image "${REGISTRY_IMAGE}"; then
                echo
                echo -e "${GREEN}✓ Deployment successful!${NC}"
                echo
            else
                echo
                echo -e "${RED}✗ Deployment failed!${NC}"
                echo
            fi
        else
            echo
            echo -e "${YELLOW}Skipping deployment.${NC}"
            echo
        fi
    else
        # No existing installation found
        echo -e "${YELLOW}⚠ No existing installation of ${APP_TITLE} found.${NC}"
        echo
        read -p "Would you like to install ${APP_TITLE} now? [y/N]: " INSTALL_NOW
        
        if [[ "${INSTALL_NOW}" =~ ^[Yy]$ ]]; then
            echo
            echo -e "${BLUE}To install ${APP_TITLE}, provide the following:${NC}"
            echo
            read -p "  Subdomain (e.g., 'parking'): " SUBDOMAIN
            read -p "  Domain (e.g., 'example.com'): " DOMAIN
            
            if [ -z "${SUBDOMAIN}" ] || [ -z "${DOMAIN}" ]; then
                echo -e "${RED}Error: Subdomain and domain are required.${NC}"
                echo
            else
                APP_ID=$(jq -r '.id' "${MANIFEST_FILE}")
                FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"
                REGISTRY_IMAGE="${REGISTRY_IMAGE_BASE}:${NEW_VERSION}"
                
                echo
                echo -e "${BLUE}Installing ${APP_TITLE} at ${FULL_DOMAIN}...${NC}"
                echo
                
                if cloudron install --app-id "${FULL_DOMAIN}" "${APP_ID}"; then
                    echo
                    echo -e "${GREEN}✓ Installation successful!${NC}"
                    echo
                else
                    echo
                    echo -e "${RED}✗ Installation failed!${NC}"
                    echo -e "${YELLOW}You can install manually with:${NC}"
                    echo "  cloudron install --app-id ${FULL_DOMAIN} ${APP_ID}"
                    echo
                fi
            fi
        else
            echo
            echo -e "${YELLOW}You can install later with:${NC}"
            echo "  cloudron install --app-id <subdomain>.<domain> <app-id>"
            echo
        fi
    fi
    
    echo -e "${YELLOW}Next steps:${NC}"
    echo
    echo "  1. Commit version changes:"
    echo "     git add CloudronManifest.json app/version.txt Dockerfile"
    echo "     git commit -m \"Bump version to ${NEW_VERSION}\""
    echo "     git push"
    echo
    echo "  2. Publish to community registry (when ready):"
    echo "     ./cloudron-publish.sh"
    echo "     (This adds the version to CloudronVersions.json)"
    echo
    echo "  3. Distribute for community:"
    echo "     Host CloudronVersions.json at a public URL and share with users"
    echo
    
    if [ ${FOUND_APP} -ne 0 ] || [ -z "${INSTALLED_APP_ID}" ]; then
        echo "  4. Install or deploy manually:"
        echo "     cloudron install --app-id <subdomain>.<domain> $(jq -r '.id' "${MANIFEST_FILE}")"
        echo
    fi
else
    echo
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                      Build Failed                             ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi
