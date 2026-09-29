#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_ROOT/build/LumaWall.app"

if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR does not exist. Run ./Scripts/package_app.sh first."
    exit 1
fi

echo "1. Installing LumaWall.app into /Applications..."
killall LumaWall 2>/dev/null || true
rm -rf /Applications/LumaWall.app
cp -R "$APP_DIR" /Applications/LumaWall.app

echo "2. Registering LumaWallWallpaperExtension with pluginkit..."
pluginkit -a /Applications/LumaWall.app/Contents/Extensions/LumaWallWallpaperExtension.appex
pluginkit -e use -i com.lumawall.app.wallpaper-extension 2>/dev/null || true

echo "3. Setting up Extension Documents container..."
CONTAINER_DIR="$HOME/Library/Containers/com.lumawall.app.wallpaper-extension/Data/Documents"
VIDEOS_DIR="$CONTAINER_DIR/videos"
mkdir -p "$VIDEOS_DIR"

# Clean up any legacy non-UUID directories (e.g. lumawall-current)
rm -rf "$VIDEOS_DIR/lumawall-current" 2>/dev/null || true

# Deploy Aurora_Loop sample wallpaper if not already deployed
SAMPLE_VIDEO="$PROJECT_ROOT/Sample Wallpapers/Aurora_Loop.mp4"
if [ -f "$SAMPLE_VIDEO" ]; then
    # Generate stable UUID for Aurora_Loop
    UUID_VAL="A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    TARGET_DIR="$VIDEOS_DIR/$UUID_VAL"
    mkdir -p "$TARGET_DIR"

    echo "Deploying sample Aurora_Loop wallpaper to $TARGET_DIR..."
    cp "$SAMPLE_VIDEO" "$TARGET_DIR/Aurora_Loop.mp4"

    # Write metadata.json matching VideoEntry Codable schema
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat << EOF > "$TARGET_DIR/metadata.json"
{
  "id": "$UUID_VAL",
  "name": "Aurora Loop",
  "filename": "Aurora_Loop.mp4",
  "duration": 5.0,
  "fps": 30.0,
  "resolution": {
    "width": 1920,
    "height": 1080
  },
  "dateAdded": 750000000
}
EOF

    # Generate thumbnail frame with Swift AVFoundation
    swift -e "
import AVFoundation
import AppKit

let videoURL = URL(fileURLWithPath: \"$TARGET_DIR/Aurora_Loop.mp4\")
let thumbURL = URL(fileURLWithPath: \"$TARGET_DIR/thumbnail.jpg\")
let asset = AVURLAsset(url: videoURL)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: 640, height: 360)

Task {
    if let (cgImage, _) = try? await gen.image(at: .zero) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? data.write(to: thumbURL)
        }
    }
    exit(0)
}
RunLoop.main.run()
" 2>/dev/null || true
fi

echo "4. Invalidating WallpaperAgent view-model cache..."
DARWIN_CACHE=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)
if [ -n "$DARWIN_CACHE" ]; then
    rm -f "$DARWIN_CACHE/com.apple.wallpaper.agent/com.apple.wallpaper.view-model-cache/extension-com.lumawall.app.wallpaper-extension-desktop"
    rm -f "$DARWIN_CACHE/com.apple.wallpaper.agent/com.apple.wallpaper.view-model-cache/extension-com.lumawall.app.wallpaper-extension-screenSaver"
fi

echo "5. Restarting WallpaperAgent..."
killall WallpaperAgent 2>/dev/null || true

echo "Installation complete! LumaWall extension registered."
