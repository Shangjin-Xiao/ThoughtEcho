#!/bin/bash
set -e

# Find flutter_quill raw_editor_state.dart in pub-cache
# Support both Linux/Mac ~/.pub-cache and Windows APPDATA or local pub-cache if possible,
# but for CI it's usually ~/.pub-cache or /home/runner/.pub-cache.
if [ -d "$PUB_CACHE" ]; then
  CACHE_DIR="$PUB_CACHE"
elif [ -d "$HOME/.pub-cache" ]; then
  CACHE_DIR="$HOME/.pub-cache"
elif [ -d "/opt/hostedtoolcache/flutter/.pub-cache" ]; then
  CACHE_DIR="/opt/hostedtoolcache/flutter/.pub-cache"
else
  CACHE_DIR="$HOME/.pub-cache"
fi

# Read the exact version of flutter_quill from pubspec.lock to be deterministic
QUILL_VERSION=""
if [ -f "pubspec.lock" ]; then
  QUILL_VERSION=$(awk '/  flutter_quill:/{flag=1;next} flag && /version:/{print $2;exit}' pubspec.lock | tr -d '"')
fi

if [ -n "$QUILL_VERSION" ]; then
  FILE=$(find "$CACHE_DIR" -path "*/flutter_quill-$QUILL_VERSION/lib/src/editor/raw_editor/raw_editor_state.dart" 2>/dev/null | head -n 1)
fi

if [ -z "$FILE" ]; then
  FILE=$(find "$CACHE_DIR" -path "*/flutter_quill-*/lib/src/editor/raw_editor/raw_editor_state.dart" 2>/dev/null | head -n 1)
fi

if [ -n "$FILE" ] && [ -f "$FILE" ]; then
  if ! grep -q "onFocusReceived" "$FILE"; then
    echo "Patching flutter_quill in $FILE"
    # Insert the missing method inside QuillRawEditorState class safely
    perl -pi -e 's/(final GlobalKey _editorKey = GlobalKey\(\);)/$1\n  \@override\n  bool onFocusReceived() => false;/g' "$FILE"
    echo "Patch applied successfully."
  else
    echo "flutter_quill is already patched."
  fi
else
  echo "flutter_quill not found in pub cache. Skipping patch."
fi
