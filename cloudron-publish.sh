#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# cloudron-publish.sh — Wrapper for publishing to Cloudron community registry
#
# This script:
#   1. Adds the current version to CloudronVersions.json
#   2. Handles release notes and version metadata
#   3. Commits the updated versions file
#   4. Reminds about distributing the versions file
#
# Note: This script should be run AFTER a successful cloudron-build.sh and after
#       manually adding release notes to CloudronVersions.json if desired.
#
# Usage:
#   ./cloudron-publish.sh
#
# Prerequisites:
#   - cloudron CLI installed and authenticated
#   - cloudron build has been run and image pushed to registry
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
VERSIONS_FILE="CloudronVersions.json"
CONFIG_FILE="deployment.config"

# ── Functions ─────────────────────────────────────────────────────────────────

# Load deployment configuration
load_deployment_config() {
    # Set defaults
    REGISTRY_IMAGE_BASE="registry.korpit.net/parking"
    
    # Load from config file if it exists
    if [ -f "${CONFIG_FILE}" ]; then
        REGISTRY_IMAGE_BASE=$(grep "^REGISTRY_IMAGE_BASE=" "${CONFIG_FILE}" | cut -d'=' -f2 | tr -d '"' || echo "registry.korpit.net/parking")
    fi
}

# ── Main script ───────────────────────────────────────────────────────────────

# Get app name from manifest
APP_TITLE=$(jq -r '.title' "${MANIFEST_FILE}" 2>/dev/null || echo "App")

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Cloudron Publish Wrapper                         ║${NC}"
echo -e "${BLUE}║                  ${APP_TITLE}                                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if required commands are available
if ! command -v cloudron &> /dev/null; then
    echo -e "${RED}Error: cloudron CLI is not installed.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq first.${NC}"
    exit 1
fi

# Load deployment configuration (for potential future use)
load_deployment_config

# Get current version from manifest
CURRENT_VERSION=$(jq -r '.version' "${MANIFEST_FILE}")

if [ -z "${CURRENT_VERSION}" ] || [ "${CURRENT_VERSION}" = "null" ]; then
    echo -e "${RED}Error: Could not extract version from ${MANIFEST_FILE}${NC}"
    exit 1
fi

echo -e "${BLUE}Publishing version: ${CURRENT_VERSION}${NC}"
echo

# Check if version already exists in CloudronVersions.json
if [ -f "${VERSIONS_FILE}" ]; then
    EXISTING_VERSION=$(jq ".[] | select(.version == \"${CURRENT_VERSION}\") | .version" "${VERSIONS_FILE}" 2>/dev/null || echo "")
    
    if [ -n "${EXISTING_VERSION}" ]; then
        echo -e "${YELLOW}⚠ Version ${CURRENT_VERSION} already exists in ${VERSIONS_FILE}${NC}"
        read -p "Update the existing version? [y/N]: " UPDATE_VERSION
        
        if [[ "${UPDATE_VERSION}" =~ ^[Yy]$ ]]; then
            echo
            echo -e "${BLUE}Running: cloudron versions update --version ${CURRENT_VERSION}${NC}"
            echo
            
            if cloudron versions update --version "${CURRENT_VERSION}"; then
                echo
                echo -e "${GREEN}✓ Version updated successfully!${NC}"
                echo
            else
                echo
                echo -e "${RED}✗ Failed to update version!${NC}"
                exit 1
            fi
        else
            echo
            echo -e "${YELLOW}Skipping version update.${NC}"
            exit 0
        fi
    else
        echo -e "${BLUE}Adding new version to ${VERSIONS_FILE}...${NC}"
        echo
        echo -e "${BLUE}Running: cloudron versions add${NC}"
        echo
        
        if cloudron versions add; then
            echo
            echo -e "${GREEN}✓ Version added successfully!${NC}"
            echo
        else
            echo
            echo -e "${RED}✗ Failed to add version!${NC}"
            exit 1
        fi
    fi
else
    echo -e "${RED}Error: ${VERSIONS_FILE} not found.${NC}"
    echo -e "${YELLOW}Run 'cloudron versions init' first to initialize the versions file.${NC}"
    exit 1
fi

# Display next steps
echo -e "${YELLOW}Next steps:${NC}"
echo
echo "  1. Review the updated ${VERSIONS_FILE}:"
echo "     git diff ${VERSIONS_FILE}"
echo
echo "  2. (Optional) Add release notes to the version entry in ${VERSIONS_FILE}"
echo
echo "  3. Commit the changes:"
echo "     git add ${VERSIONS_FILE}"
echo "     git commit -m \"Publish version ${CURRENT_VERSION}\""
echo "     git push"
echo
echo "  4. Distribute the versions file:"
echo "     • Host CloudronVersions.json at a publicly accessible URL"
echo "     • Share the URL: https://your-domain/path/to/CloudronVersions.json"
echo "     • Users can add it in their Cloudron dashboard under Community apps"
echo
echo "  5. (Optional) Post about the release in the Cloudron forum:"
echo "     https://forum.cloudron.io/category/96/app-packaging-development"
echo
