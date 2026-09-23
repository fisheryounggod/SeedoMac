#!/bin/bash
set -e

# Configuration
APP_NAME="Seedo"
BUNDLE_ID="tech.seedo.mac"
PROJECT_DIR=$(pwd)
BUILD_DIR="${PROJECT_DIR}/build"
DMG_NAME="Seedo_v2.3.12.dmg"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

# Use an explicit distribution identity for a signed release. Leaving this
# unset keeps the existing ad-hoc DMG workflow for local testing only.
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

echo "🧹 Cleaning previous builds..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_NAME}"
mkdir -p "${BUILD_DIR}"

# 1. Regenerate Project (if xcodegen exists)
XCODEGEN=$(which xcodegen || echo "/opt/homebrew/bin/xcodegen")
if [ -f "$XCODEGEN" ]; then
    echo "🏗️ Regenerating project with xcodegen..."
    $XCODEGEN generate
else
    echo "⚠️ xcodegen not found, skipping regeneration..."
fi

# 2. Archive
echo "📦 Archiving ${APP_NAME}..."
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${PROJECT_DIR}/temp_derived_data" \
    CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
    CODE_SIGN_STYLE="Manual"

# 3. Export
echo "🚀 Exporting App from Archive..."
mkdir -p "${EXPORT_PATH}"
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_PATH}/"

if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "⚠️ Using ad-hoc signing. This DMG is for local testing and cannot pass Mac App Store/pkg validation."
else
    echo "✅ Archive signed with ${SIGNING_IDENTITY}; preserving Xcode's embedded entitlements."
    codesign --verify --deep --strict "${APP_PATH}"
fi

# 4. Create DMG
echo "💿 Creating DMG: ${DMG_NAME}..."
rm -f "${DMG_NAME}"

# Add Applications shortcut for drag-to-install
ln -s /Applications "${EXPORT_PATH}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${EXPORT_PATH}" -ov -format UDZO "${DMG_NAME}"

echo "✅ Build Complete: ${DMG_NAME}"
