#!/bin/bash
set -e

APP_NAME="SeedoMac"
VERSION="2.0.1"
DMG_NAME="SeedoMac_v${VERSION}.dmg"
BUILD_DIR="build"
EXPORT_DIR="${BUILD_DIR}/Export"

# Clean up previous build
rm -rf "${BUILD_DIR}"

# 1. Clean and Build
echo "Building SeedoMac..."
xcodebuild clean archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    -derivedDataPath temp_derived_data \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS=""

# 2. Export App
echo "Exporting App..."
mkdir -p "${EXPORT_DIR}"
cp -R "${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "${EXPORT_DIR}/"

# 3. Create DMG
echo "Creating DMG..."
if [ -f "${DMG_NAME}" ]; then
    rm "${DMG_NAME}"
fi

DMG_STAGING="${BUILD_DIR}/DMG_Staging"
mkdir -p "${DMG_STAGING}"
cp -R "${EXPORT_DIR}/${APP_NAME}.app" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_NAME}"

echo "DMG created: ${DMG_NAME}"
