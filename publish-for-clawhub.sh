#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$REPO_ROOT/cloud-backup"

echo "Preparing ClawHub bundle..."

rm -rf "$OUT"
mkdir -p "$OUT"

cp "$REPO_ROOT/SKILL.md" "$OUT/"
cp -r "$REPO_ROOT/scripts" "$OUT/scripts"
cp -r "$REPO_ROOT/references" "$OUT/references"

echo "Created: $OUT"
ls -R "$OUT"
echo ""
echo "Upload this folder: $OUT"
