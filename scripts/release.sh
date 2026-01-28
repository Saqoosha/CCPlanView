#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"

usage() {
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

VERSION="$1"
TAG="v${VERSION}"

# Validate version format (X.Y.Z)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid version format. Use X.Y.Z (e.g., 1.0.0)"
  exit 1
fi

cd "$ROOT_DIR"

echo "=== Releasing CCPlanView ${VERSION} ==="

# Get current build number and increment
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *"\([0-9]*\)".*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "=== Bumping version to ${VERSION} (build ${NEW_BUILD}) ==="

# Update version in project.yml
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"${VERSION}\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" project.yml

echo "=== Building and packaging DMG ==="
"${ROOT_DIR}/scripts/package_dmg.sh"

DMG_PATH="${BUILD_DIR}/CCPlanView.dmg"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: DMG not found at $DMG_PATH"
  exit 1
fi

echo "=== Creating commit and tag ==="
jj describe -m "Release ${VERSION}

- Bump version to ${VERSION} (build ${NEW_BUILD})

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

# Move main bookmark to current commit and push
jj bookmark set main -r @
jj new
jj git push --bookmark main

# Create and push git tag
git tag "$TAG"
git push origin "$TAG"

echo "=== Creating GitHub Release ==="
gh release create "$TAG" "$DMG_PATH" \
  --title "CCPlanView ${VERSION}" \
  --notes "$(cat <<EOF
## CCPlanView ${VERSION}

### Changes
- (Add release notes here)
EOF
)"

echo "=== Release complete ==="
echo "Version: ${VERSION}"
echo "Tag: ${TAG}"
echo "DMG: ${DMG_PATH}"
echo ""
echo "Don't forget to update the release notes on GitHub!"
