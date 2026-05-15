#!/usr/bin/env bash
# Regenerate iOS AppIcon.appiconset from:
#   app-icon-light.png  (light / universal, 1024×1024)
#   app-icon-dark.png   (dark appearance, optional, 1024×1024)
# Uses the modern single-size universal format — Xcode scales automatically.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LIGHT_SRC="${ROOT}/app-icon-light.png"
DARK_SRC="${ROOT}/app-icon-dark.png"
DEST="${ROOT}/Sources/PPR/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$LIGHT_SRC" ]]; then
  echo "error: missing $LIGHT_SRC — place your master square PNG there (1024×1024)." >&2
  exit 1
fi

mkdir -p "$DEST"
rm -f "$DEST"/*.png

# Flatten alpha channel (App Store rejects alpha on marketing icons).
flatten() {
  local src="$1" out="$2"
  if sips -g hasAlpha "$src" 2>/dev/null | grep -q "hasAlpha: yes"; then
    local tmp; tmp="$(mktemp -t ppr_icon).jpg"
    sips -s format jpeg "$src" --out "$tmp" >/dev/null
    sips -s format png "$tmp" --out "$out" >/dev/null
    rm -f "$tmp"
  else
    cp "$src" "$out"
  fi
}

flatten "$LIGHT_SRC" "$DEST/ios_marketing_1024.png"

HAS_DARK=false
if [[ -f "$DARK_SRC" ]]; then
  HAS_DARK=true
  flatten "$DARK_SRC" "$DEST/ios_marketing_1024_dark.png"
fi

/usr/bin/python3 - "$DEST" "$HAS_DARK" <<'PY'
import json, sys
from pathlib import Path

dest = Path(sys.argv[1])
has_dark = sys.argv[2] == "true"

images = [
    {
        "filename": "ios_marketing_1024.png",
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024"
    }
]

if has_dark:
    images.append({
        "appearances": [{"appearance": "luminosity", "value": "dark"}],
        "filename": "ios_marketing_1024_dark.png",
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024"
    })

payload = {"images": images, "info": {"author": "xcode", "version": 1}}
(dest / "Contents.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

echo "Wrote App Icon set → $DEST (dark=$HAS_DARK)"
