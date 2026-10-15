#!/bin/sh
# Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>
# Builds AppIcon.icns from the Macpad++ logo (any image format NSImage reads).
# usage: make_icon.sh <logo image> <outdir>
set -e
LOGO="$1"; OUT="$2"
SET="$OUT/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
swift "$(dirname "$0")/make_icon.swift" "$LOGO" "$OUT/icon_base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon_base.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$OUT/icon_base.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$OUT/AppIcon.icns"
rm -rf "$SET" "$OUT/icon_base.png"
