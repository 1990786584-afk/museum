#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/preview"
fail(){ echo "Preview check FAILED: $*" >&2; exit 1; }

test -f "$OUT/index.html" || fail "home missing"
test -f "$OUT/gallery/index.html" || fail "gallery missing"
test -f "$OUT/gallery/photos.json" || fail "gallery example data missing"
test -f "$OUT/dates/index.html" || fail "Ephemera demo missing"
test -f "$OUT/romance/index.html" || fail "date invitation missing"
test -f "$OUT/romance/flow.js" || fail "bouquet flow missing"
test -f "$OUT/romance/style.css" || fail "date stationery missing"
test -f "$OUT/museum-assets/ephemera-envelope.jpg" || fail "original envelope missing"
test -f "$OUT/credits/shelf/LICENSE" || fail "Shelf license missing"
test -f "$OUT/credits/ephemera/LICENSE" || fail "Ephemera license missing"

# Guard against an accidental restyle of the upstream gallery.
cmp -s "$OUT/gallery/index.html" "$ROOT/sources/shelf-in-the-sky/index.html" || fail "upstream gallery HTML changed"
cmp -s "$OUT/gallery/assets/sky.webp" "$ROOT/sources/shelf-in-the-sky/assets/sky.webp" || fail "upstream painting changed"
cmp -s "$OUT/gallery/photos.json" "$ROOT/sources/shelf-in-the-sky/photos.json" || fail "upstream gallery sample changed"
cmp -s "$OUT/museum-assets/ephemera-envelope.jpg" "$ROOT/sources/ephemera-date/docs/images/01-envelope.jpg" || fail "upstream invitation artwork changed"

# Verify both 3D flowers, stage transitions, and private date routing.
node --check "$OUT/romance/flow.js" || fail "flower/date flow script invalid"
node --test "$ROOT/tests/romance-flow.test.cjs" || fail "flower/date stage tests failed"
# The upstream flower renderer stays on its own origin; no unlicensed bundle in Pages.
test ! -d "$OUT/flowers" || fail "flower shop unexpectedly copied"
grep -q 'https://frycarrot.github.io/CyberFlowerShop/' "$OUT/romance/flow.js" || fail "original florist not embedded"

# Private data is never included in a public preview.
test ! -d "$OUT/private" || fail "private folder leaked"
find "$OUT" -type f \( -name '.env' -o -name '*.pem' -o -name '*secret*' \) | grep -q . && fail "private configuration leaked"
echo "Preview check OK — original exhibitions + gift-date flow, original artwork and licenses present."
