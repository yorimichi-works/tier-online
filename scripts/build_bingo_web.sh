#!/usr/bin/env sh
# Builds Bingo Online (lib/main_bingo.dart) into build/bingo_web.
#
# The Flutter project's web/ folder belongs to tier-online, so after the build
# the bingo-specific shell (web_bingo/) replaces index.html and manifest.json.
set -eu

cd "$(dirname "$0")/.."
OUT=build/bingo_web
BASE_HREF="${BASE_HREF:-/}"

flutter build web --release --no-wasm-dry-run \
  -t lib/main_bingo.dart \
  -o "$OUT" \
  --base-href "$BASE_HREF" \
  "$@"

sed "s#\$FLUTTER_BASE_HREF#${BASE_HREF}#" web_bingo/index.html > "$OUT/index.html"
cp web_bingo/manifest.json "$OUT/manifest.json"
# tier-online only files that must not be served by the bingo site.
rm -f "$OUT/ads.txt" "$OUT/og-image-ja.png" "$OUT/og-image-ko.png" "$OUT/og-image-en.png"

echo "Bingo Online built into $OUT"
