#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"

CONFIGURATION="${1:-Debug}"

mkdir -p "${BUILD_DIR}"

# Regenerate Xcode project from project.yml
xcodegen generate --spec "${ROOT_DIR}/project.yml"

# Override signing for command-line builds so we don't depend on a
# provisioning profile or a stale Mac Development cert. Release uses
# Developer ID Application (notarization-ready); Debug uses ad-hoc.
if [[ "${CONFIGURATION}" == "Release" ]]; then
  SIGN_ARGS=(
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=Developer ID Application: Whatever Co. (G5G54TCH8W)"
  )
else
  SIGN_ARGS=(
    "CODE_SIGN_IDENTITY=-"
    "CODE_SIGNING_REQUIRED=NO"
    "CODE_SIGNING_ALLOWED=NO"
  )
fi

xcodebuild \
  -scheme CCPlanView \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  "${SIGN_ARGS[@]}" \
  build

echo "Built app:"
echo "${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/CCPlanView.app"
