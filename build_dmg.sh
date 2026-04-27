#!/bin/bash
set -e

# Configuration
APP_NAME="Seedo"
BUNDLE_ID="tech.seedo.mac"
PROJECT_DIR=$(pwd)
BUILD_DIR="${PROJECT_DIR}/build"
DMG_NAME="Seedo_v2.2.8.dmg"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

echo "🧹 Cleaning previous builds..."
rm -rf "${BUILD_DIR}"
rm -f "Seedo_v2.0.1.dmg" "Seedo_v2.0.2.dmg" "Seedo_v2.0.3.dmg" "Seedo_v2.0.4.dmg" "Seedo_v2.0.5.dmg" "Seedo_v2.0.6.dmg" "Seedo_v2.0.7.dmg" "Seedo_v2.0.8.dmg" "Seedo_v2.0.9.dmg" "Seedo_v2.1.0.dmg" "Seedo_v2.1.1.dmg" "Seedo_v2.1.2.dmg" "Seedo_v2.1.3.dmg" "Seedo_v2.1.4.dmg" "Seedo_v2.1.5.dmg" "Seedo_v2.1.6.dmg"
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
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual"

# 3. Export
echo "🚀 Exporting App from Archive..."
mkdir -p "${EXPORT_PATH}"
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_PATH}/"

echo "✍️ Applying Ad-hoc Signing with Entitlements..."
codesign --force --deep --sign - --entitlements "SeedoMac/Seedo.entitlements" "${APP_PATH}"

# 4. Create DMG
echo "💿 Creating DMG: ${DMG_NAME}..."
rm -f "${DMG_NAME}"

# Add Applications shortcut for drag-to-install
ln -s /Applications "${EXPORT_PATH}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${EXPORT_PATH}" -ov -format UDZO "${DMG_NAME}"

echo "✅ Build Complete: ${DMG_NAME}"
