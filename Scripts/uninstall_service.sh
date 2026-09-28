#!/bin/bash
set -e

# LumaWall Background Daemon Uninstaller
echo "=== Uninstalling LumaWall Background Service ==="

USER_ID="$(id -u)"
PLIST_FILE="$HOME/Library/LaunchAgents/com.lumawall.app.plist"

# 1. Unload from launchd
echo "1. Stopping and unregistering background service..."
launchctl bootout "gui/$USER_ID/com.lumawall.app" 2>/dev/null || true
launchctl unload "$PLIST_FILE" 2>/dev/null || true

# 2. Remove plist
if [ -f "$PLIST_FILE" ]; then
    echo "2. Removing $PLIST_FILE..."
    rm -f "$PLIST_FILE"
fi

# 3. Kill any remaining process
pkill -x "LumaWall" 2>/dev/null || true

echo "✅ LumaWall background service has been completely uninstalled."
echo "   (The app in /Applications/LumaWall.app remains available if you want to run it manually.)"
