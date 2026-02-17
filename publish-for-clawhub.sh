#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$REPO_ROOT/clawhub-bundle"

REQUIRED_FILES=(
  "SKILL.md"
  "scripts/openclaw-cloud-backup.sh"
  "references/provider-setup.md"
  "references/security-troubleshooting.md"
  "references/local-config.md"
)

echo "Preparing ClawHub bundle..."

for relative_path in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$REPO_ROOT/$relative_path" ]; then
    echo "Error: required file is missing: $relative_path" >&2
    exit 1
  fi
done

rm -rf "$OUT"
mkdir -p "$OUT/scripts" "$OUT/references"

cp "$REPO_ROOT/SKILL.md" "$OUT/"
cp "$REPO_ROOT/scripts/openclaw-cloud-backup.sh" "$OUT/scripts/"
cp "$REPO_ROOT/references/provider-setup.md" "$OUT/references/"
cp "$REPO_ROOT/references/security-troubleshooting.md" "$OUT/references/"
cp "$REPO_ROOT/references/local-config.md" "$OUT/references/"

echo "Created: $OUT"
echo "Bundle contents:"
ls -R "$OUT"
echo ""
echo "Upload this folder in ClawHub:"
echo "  $OUT"
