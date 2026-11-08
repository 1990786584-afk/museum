#!/usr/bin/env bash
# Compose the original applications unchanged. No private content is copied.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="/museum"
if [ "$#" -gt 0 ]; then BASE="$1"; fi
OUT="$ROOT/preview"

test -f "$ROOT/sources/shelf-in-the-sky/index.html" || { echo "Missing git submodules: git submodule update --init --recursive" >&2; exit 1; }
test -f "$ROOT/sources/ephemera-date/web/package.json" || { echo "Missing Ephemera submodule" >&2; exit 1; }

# Do not carry stale build artifacts, or anything private.
rm -rf "$OUT"
mkdir -p "$OUT/gallery" "$OUT/dates" "$OUT/museum-assets" "$OUT/romance"
cp "$ROOT/index.html" "$OUT/index.html"
# Date story is our own orchestration only; CyberFlowerShop remains hosted by its author.
cp "$ROOT/romance/index.html" "$ROOT/romance/style.css" "$ROOT/romance/flow.js" "$OUT/romance/"
cp "$ROOT/sources/ephemera-date/docs/images/01-envelope.jpg" "$OUT/museum-assets/ephemera-envelope.jpg"
cp "$ROOT/sources/ephemera-date/docs/images/05-box.jpg" "$OUT/museum-assets/ephemera-box.jpg"

# The complete original gallery UI + sample artwork; copy without modifying any files.
# Exclude its server/tools to avoid publishing executable tools.
(
 cd "$ROOT/sources/shelf-in-the-sky"
 tar --exclude='./.git' --exclude='./server' --exclude='./tools' --exclude='./docs' --exclude='./LICENSE' --exclude='./README.md' -cf - .
) | (cd "$OUT/gallery" && tar -xf -)

# Ephemera's own demo build is visually identical to its upstream demo.
# It uses stock demo data + accelerated time. Never a private backend.
(
 cd "$ROOT/sources/ephemera-date/web"
 if [ ! -d node_modules ]; then npm ci --no-audit --no-fund 1>&2; fi
 EPHEMERA_WEB_BASE="$BASE/dates" npm run build:demo 1>&2
 tar -C dist-demo -cf - .
) | (cd "$OUT/dates" && tar -xf -)

# Keep upstream licensing and credits available to visitors.
mkdir -p "$OUT/credits/shelf" "$OUT/credits/ephemera"
cp "$ROOT/LICENSES.md" "$OUT/credits/index.md"
cp "$ROOT/sources/shelf-in-the-sky/LICENSE" "$OUT/credits/shelf/LICENSE"
cp "$ROOT/sources/shelf-in-the-sky/README.md" "$OUT/credits/shelf/README.md"
for f in LICENSE LICENSE-CONTENT NOTICE LICENSING.md; do
 cp "$ROOT/sources/ephemera-date/$f" "$OUT/credits/ephemera/$f"
done

"$ROOT/scripts/check-preview.sh"
printf 'Museum demo prepared: %s (base path: %s)\n' "$OUT" "$BASE"
