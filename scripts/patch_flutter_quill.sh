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

FILE=$(find "$CACHE_DIR" -path "*/flutter_quill-*/lib/src/editor/raw_editor/raw_editor_state.dart" 2>/dev/null | head -n 1)

if [ -n "$FILE" ] && [ -f "$FILE" ]; then
  if ! grep -q "onFocusReceived" "$FILE"; then
    echo "Patching flutter_quill in $FILE"
    # Insert the missing method inside QuillRawEditorState class safely
    sed -i -e '/final GlobalKey _editorKey = GlobalKey();/a \ \ @override\n  bool onFocusReceived() => false;' "$FILE"
    echo "Patch applied successfully."
  else
    echo "flutter_quill is already patched."
  fi
else
  echo "flutter_quill not found in pub cache. Skipping patch."
fi
