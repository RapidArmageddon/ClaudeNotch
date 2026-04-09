#!/bin/bash
# Build ClaudeNotch and create .app bundle
set -euo pipefail

PRODUCT_NAME="ClaudeNotch"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

SIGN_IDENTITY="Developer ID Application: Louis Deleuil (9NY6UBGL5T)"
NOTARIZE_PROFILE="ClaudeNotch"

echo "Building $PRODUCT_NAME..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# Copy binary
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"

# Copy Info.plist
cp Sources/Info.plist "$CONTENTS_DIR/Info.plist"

# Copy Sparkle framework into the app bundle
SPARKLE_FRAMEWORK=$(find .build -path "*/Sparkle.framework" -maxdepth 5 -type d | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    echo "Copying Sparkle framework..."
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
fi

# Fix rpath so the binary can find Sparkle.framework in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$PRODUCT_NAME" 2>/dev/null || true

# --- Code Signing ---
echo "Signing with: $SIGN_IDENTITY"
CODESIGN="codesign --force --options runtime --timestamp --sign"

# Sign Sparkle components inside-out (nested code must be signed before outer bundle)
if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    # Sign all standalone executables (e.g. Autoupdate)
    find "$FRAMEWORKS_DIR/Sparkle.framework" -type f -perm +111 ! -name "*.dylib" | while read -r bin; do
        file "$bin" | grep -q "Mach-O" && $CODESIGN "$SIGN_IDENTITY" "$bin"
    done
    # Sign XPC services
    find "$FRAMEWORKS_DIR/Sparkle.framework" -name "*.xpc" -type d | while read -r xpc; do
        $CODESIGN "$SIGN_IDENTITY" "$xpc"
    done
    # Sign helper apps
    find "$FRAMEWORKS_DIR/Sparkle.framework" -name "*.app" -type d | while read -r app; do
        $CODESIGN "$SIGN_IDENTITY" "$app"
    done
    # Sign the framework itself
    $CODESIGN "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework"
fi

# Sign the main app bundle
$CODESIGN "$SIGN_IDENTITY" "$APP_DIR"

echo "Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"
echo "Signature valid."

echo ""
echo "App bundle created at: $APP_DIR"
echo "To run: open $APP_DIR"

# --- Notarization (--notarize flag) ---
if [ "${1:-}" = "--notarize" ] || [ "${1:-}" = "--release" ]; then
    echo ""
    echo "Creating zip for notarization..."
    cd "$BUILD_DIR"
    rm -f "$PRODUCT_NAME.zip"
    ditto -c -k --keepParent "$PRODUCT_NAME.app" "$PRODUCT_NAME.zip"
    cd - > /dev/null

    echo "Submitting for notarization..."
    xcrun notarytool submit "$BUILD_DIR/$PRODUCT_NAME.zip" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_DIR"

    echo "Verifying notarization..."
    spctl --assess --verbose=4 --type execute "$APP_DIR"

    echo ""
    echo "Notarization complete. App is ready for distribution."

    # Re-create zip with stapled ticket for release
    cd "$BUILD_DIR"
    rm -f "$PRODUCT_NAME.zip"
    ditto -c -k --keepParent "$PRODUCT_NAME.app" "$PRODUCT_NAME.zip"
    cd - > /dev/null
    echo "Release zip: $BUILD_DIR/$PRODUCT_NAME.zip"
fi

# --- Sparkle update signature (--sign-update or --release flag) ---
SIGN_UPDATE=$(find .build -name "sign_update" -type f | head -1)
if [ -n "$SIGN_UPDATE" ] && { [ "${1:-}" = "--sign-update" ] || [ "${1:-}" = "--release" ]; }; then
    echo ""
    echo "Generating Sparkle update signature..."
    if [ ! -f "$BUILD_DIR/$PRODUCT_NAME.zip" ]; then
        cd "$BUILD_DIR"
        ditto -c -k --keepParent "$PRODUCT_NAME.app" "$PRODUCT_NAME.zip"
        cd - > /dev/null
    fi
    "$SIGN_UPDATE" "$BUILD_DIR/$PRODUCT_NAME.zip"
fi
