#!/usr/bin/env bash
set -euo pipefail

echo "=== Dictate — odinstalace ==="

# Stop any active recording
if [[ -f /tmp/dictate_rec.pid ]]; then
    kill "$(cat /tmp/dictate_rec.pid)" 2>/dev/null || true
    rm -f /tmp/dictate_rec.pid /tmp/dictate_recording.raw /tmp/dictate_recording.wav
fi

# Quit Dictate app
pkill -f "Dictate.app/Contents/MacOS/Dictate" 2>/dev/null || true

# Uninstall brew packages
echo ""
read -p "Odinstalovat whisper-cpp a sox? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    brew uninstall whisper-cpp sox 2>/dev/null || true
    echo "Odinstalováno: whisper-cpp, sox"
fi

# Remove dictate directory
DICTATE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "Mažu: $DICTATE_DIR"
rm -rf "$DICTATE_DIR"

echo ""
echo "Nezapomeň odebrat Dictate z Accessibility v System Settings."
echo "Hotovo."
