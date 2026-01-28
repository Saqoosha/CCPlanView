#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"

CONFIGURATION="${1:-Debug}"

mkdir -p "${BUILD_DIR}"

# Regenerate Xcode project from project.yml
xcodegen generate --spec "${ROOT_DIR}/project.yml"

xcodebuild \
  -scheme CCPlanView \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build

echo "Built app:"
echo "${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/CCPlanView.app"
