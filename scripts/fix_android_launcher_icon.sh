#!/usr/bin/env bash
set -euo pipefail

# Fix Android adaptive icon inset that can cause visible "padding/white border".
# flutter_launcher_icons may regenerate android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
# with a <foreground><inset ... android:inset="16%"/></foreground> wrapper.
# This script rewrites it back to the standard form:
#   <foreground android:drawable="@drawable/ic_launcher_foreground"/>

FILE="android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"

if [[ ! -f "$FILE" ]]; then
  echo "[fix_android_launcher_icon] Not found: $FILE" >&2
  exit 1
fi

# Only patch if it contains the 16% inset pattern.
if ! grep -q 'android:inset="16%"' "$FILE"; then
  echo "[fix_android_launcher_icon] No 16% inset found. Nothing to do."
  exit 0
fi

python3 - <<'PY'
from pathlib import Path
import re

path = Path("android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml")
text = path.read_text(encoding="utf-8")

# Replace the whole <foreground>...</foreground> block containing an inset with a single-line drawable reference.
pattern = re.compile(r"<foreground>\s*<inset\s+android:drawable=\"@drawable/ic_launcher_foreground\"\s+android:inset=\"16%\"\s*/>\s*</foreground>", re.MULTILINE)
new_text, n = pattern.subn('<foreground android:drawable="@drawable/ic_launcher_foreground"/>', text)

if n == 0:
  raise SystemExit("[fix_android_launcher_icon] Pattern not found; file format changed.")

path.write_text(new_text, encoding="utf-8")
print(f"[fix_android_launcher_icon] Patched {path} (replaced {n} block(s)).")
PY
