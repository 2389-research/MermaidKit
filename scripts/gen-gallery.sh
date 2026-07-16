#!/usr/bin/env bash
# Regenerates docs/images from the fixtures: hero (light/dark) plus one
# standalone image per diagram type in docs/images/types/ (light + dark).
# Requires ImageMagick for palette quantization.
set -euo pipefail
cd "$(dirname "$0")/.."
GEN_DOC_IMAGES=1 swift test --filter DocImageGeneration
cd docs/images
# Flat-color diagrams quantize to 8-bit with no visible loss — ~4x smaller.
for f in hero-light.png hero-dark.png; do
  magick "$f" -resize 2200 -colors 255 -define png:compression-level=9 "$f"
done
for f in types/*.png; do
  magick "$f" -resize '2000>' -colors 255 -define png:compression-level=9 "$f"
done
rm -f gallery.png
echo "docs/images: hero-light.png hero-dark.png + $(ls types/*.png | wc -l | tr -d ' ') per-type images"
