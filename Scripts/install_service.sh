#!/bin/bash
set -e

# LumaWall Background Daemon / LaunchAgent Installer
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== LumaWall Background Daemon Installer ==="

# 1. Package the Application Bundle
echo "1. Packaging LumaWall.app..."
"$PROJECT_ROOT/Scripts/package_app.sh"

APP_SOURCE="$PROJECT_ROOT/build/LumaWall.app"
APP_DEST="/Applications/LumaWall.app"

# 2. Install to /Applications
echo "2. Installing to $APP_DEST..."
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

# 3. Create LaunchAgents Directory
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$HOME/Library/Logs"

PLIST_FILE="$LAUNCH_AGENTS_DIR/com.lumawall.app.plist"
USER_ID="$(id -u)"

# 4. Generate LaunchAgent Plist (Like MySQL/Docker Background Daemons)
echo "3. Creating LaunchAgent configuration at $PLIST_FILE..."
cat << EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lumawall.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/LumaWall.app/Contents/MacOS/LumaWall</string>
        <string>--background</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/LumaWall.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/LumaWall.error.log</string>
</dict>
</plist>
EOF

# 5. Bootout existing instance if loaded
echo "4. Registering background service with macOS launchd..."
launchctl bootout "gui/$USER_ID/com.lumawall.app" 2>/dev/null || true
launchctl unload "$PLIST_FILE" 2>/dev/null || true

# 6. Bootstrap and start service
launchctl bootstrap "gui/$USER_ID" "$PLIST_FILE" 2>/dev/null || launchctl load -w "$PLIST_FILE"

echo ""
echo "✅ LumaWall is now running continuously as a macOS Background Service!"
echo "   - Starts automatically on laptop boot / login."
echo "   - Runs silently in the background (no Dock icon, Menu Bar icon ✨)."
echo "   - Restores live wallpaper automatically."
echo "   - Logs available at: $HOME/Library/Logs/LumaWall.log"
echo ""
echo "To uninstall, run: ./Scripts/uninstall_service.sh"
