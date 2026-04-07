#!/bin/bash
# Build ClaudeNotch and create .app bundle
set -euo pipefail

PRODUCT_NAME="ClaudeNotch"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "Building $PRODUCT_NAME..."
swift build -c release

echo "Creating app bundle..."
mkdir -p "$MACOS_DIR"

# Copy binary
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"

# Copy Info.plist
cp Sources/Info.plist "$CONTENTS_DIR/Info.plist"

echo "App bundle created at: $APP_DIR"
echo "To run: open $APP_DIR"
