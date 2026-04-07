#!/bin/bash
# Build ClaudeNotch and create .app bundle
set -euo pipefail

PRODUCT_NAME="ClaudeNotch"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "Building $PRODUCT_NAME..."
swift build -c release

echo "Creating app bundle..."
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

# Ad-hoc sign (sign frameworks first, then the app)
codesign --force --deep --sign - "$APP_DIR"

echo "App bundle created at: $APP_DIR"
echo "To run: open $APP_DIR"

# Generate update signature if sign_update tool is available
SIGN_UPDATE=$(find .build -name "sign_update" -type f | head -1)
if [ -n "$SIGN_UPDATE" ] && [ "${1:-}" = "--sign-update" ]; then
    echo ""
    echo "Generating update signature..."
    cd "$BUILD_DIR"
    rm -f "$PRODUCT_NAME.zip"
    zip -r "$PRODUCT_NAME.zip" "$PRODUCT_NAME.app"
    cd - > /dev/null
    "$SIGN_UPDATE" "$BUILD_DIR/$PRODUCT_NAME.zip"
fi
