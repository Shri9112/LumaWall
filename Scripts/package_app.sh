#!/bin/bash
set -e

# Package LumaWall into native .app bundle
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_DIR="$PROJECT_ROOT/.build"
CACHE_DIR="$BUILD_DIR/cache"
mkdir -p "$CACHE_DIR"

echo "Building LumaWallKit module..."
swiftc -module-cache-path "$CACHE_DIR" -target arm64-apple-macos26.0 \
    -O -emit-module -emit-library -module-name LumaWallKit \
    "$PROJECT_ROOT"/Sources/LumaWallKit/**/*.swift \
    -o "$BUILD_DIR/libLumaWallKit.dylib" \
    -I "$BUILD_DIR"

echo "Building LumaWall binary..."
swiftc -module-cache-path "$CACHE_DIR" -target arm64-apple-macos26.0 \
    -O -parse-as-library \
    -I "$BUILD_DIR" -L "$BUILD_DIR" -lLumaWallKit \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -Xlinker -rpath -Xlinker @loader_path \
    "$PROJECT_ROOT"/Sources/LumaWall/**/*.swift \
    -o "$BUILD_DIR/LumaWall"

APP_DIR="$PROJECT_ROOT/build/LumaWall.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BUILD_DIR/LumaWall" "$MACOS_DIR/LumaWall"
chmod +x "$MACOS_DIR/LumaWall"
cp "$BUILD_DIR/libLumaWallKit.dylib" "$FRAMEWORKS_DIR/libLumaWallKit.dylib"

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LumaWall</string>
    <key>CFBundleIdentifier</key>
    <string>com.lumawall.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LumaWall</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.lumawall.app</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>lumawall</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Build and embed LumaWallWallpaperExtension.appex
EXT_DIR="$APP_DIR/Contents/Extensions/LumaWallWallpaperExtension.appex"
echo "Building LumaWallWallpaperExtension (macOS 26+ Lock Screen live engine)..."
mkdir -p "$EXT_DIR/Contents/MacOS"
swiftc -module-cache-path "$CACHE_DIR" -target arm64-apple-macos26.0 -parse-as-library -O \
    -import-objc-header "$PROJECT_ROOT/Sources/LumaWallWallpaperExtension/WallpaperExtension-Bridging-Header.h" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$PROJECT_ROOT"/Sources/LumaWallWallpaperExtension/*.swift \
    -o "$EXT_DIR/Contents/MacOS/LumaWallWallpaperExtension"
cp "$PROJECT_ROOT/Sources/LumaWallWallpaperExtension/Info.plist" "$EXT_DIR/Contents/Info.plist"
echo "XPC!" > "$EXT_DIR/Contents/PkgInfo"

# Codesign Frameworks
codesign -s - -f "$FRAMEWORKS_DIR/libLumaWallKit.dylib"

# Codesign extension with App Sandbox entitlement (strictly required by ExtensionFoundation in macOS 15/26)
echo "Signing LumaWallWallpaperExtension with App Sandbox entitlement..."
codesign -s - -f --entitlements "$PROJECT_ROOT/Sources/LumaWallWallpaperExtension/LumaWallWallpaperExtension.entitlements" "$EXT_DIR"

# Codesign parent app bundle
codesign -s - -f "$APP_DIR"

echo "LumaWall.app successfully packaged at: $APP_DIR"

