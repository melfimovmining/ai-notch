#!/bin/bash
# Installs AI Notch and sets it to open at login.
#
#   ./install.sh              install to /Applications (or ~/Applications)
#   ./install.sh --no-login   install without registering the login item
#   ./install.sh --uninstall  remove the login item and the installed copy
#
# The login item points at wherever the app is installed, so always install
# first and register second — which is what this script does.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AI Notch.app"
EXEC="AI Notch"
LEGACY_NAME="SideNotch.app"          # what this app was called before
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
INSTALLED="$DEST/$APP_NAME"
LEGACY="$DEST/$LEGACY_NAME"

register_login=1
uninstall=0
for arg in "$@"; do
  case "$arg" in
    --no-login)  register_login=0 ;;
    --uninstall) uninstall=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Drop stale login registrations: they name a bundle path, not just an app.
for old in "$INSTALLED/Contents/MacOS/$EXEC" "$LEGACY/Contents/MacOS/SideNotch"; do
  [ -x "$old" ] && "$old" --unregister-login >/dev/null 2>&1 || true
done
pkill -x "$EXEC" 2>/dev/null || true
pkill -x SideNotch 2>/dev/null || true
rm -rf "$LEGACY"

if [ "$uninstall" = 1 ]; then
  rm -rf "$INSTALLED"
  echo "Removed $INSTALLED and its login item."
  exit 0
fi

./build.sh >/dev/null
mkdir -p "$DEST"
rm -rf "$INSTALLED"
cp -R "build/$APP_NAME" "$INSTALLED"

# Re-sign in place: the signature covers the bundle, and copying can disturb it.
codesign --force --sign - "$INSTALLED" >/dev/null 2>&1 || true

# Nudge Launch Services so Finder picks up the new name and icon immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$INSTALLED" >/dev/null 2>&1 || true

echo "Installed $INSTALLED"

if [ "$register_login" = 1 ]; then
  "$INSTALLED/Contents/MacOS/$EXEC" --register-login
else
  echo "Open at Login: skipped (--no-login)"
fi

open "$INSTALLED"
echo "Running. Right-click the tab for 'Open at Login' and 'Quit AI Notch'."
