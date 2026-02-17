#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$REPO_ROOT/clawhub-bundle"

REQUIRED_FILES=(
  "SKILL.md"
  "scripts/cloud-backup.sh"
  "references/security.md"
  "references/providers/aws-s3.md"
  "references/providers/cloudflare-r2.md"
  "references/providers/backblaze-b2.md"
  "references/providers/minio.md"
  "references/providers/digitalocean-spaces.md"
)

echo "Preparing ClawHub bundle..."

for f in "${REQUIRED_FILES[@]}"; do
  [ -f "$REPO_ROOT/$f" ] || { echo "Error: missing $f" >&2; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT/scripts" "$OUT/references/providers"

cp "$REPO_ROOT/SKILL.md" "$OUT/"
cp "$REPO_ROOT/scripts/cloud-backup.sh" "$OUT/scripts/"
cp "$REPO_ROOT/references/security.md" "$OUT/references/"
cp "$REPO_ROOT/references/providers/"*.md "$OUT/references/providers/"

echo "Created: $OUT"
ls -R "$OUT"
echo ""
echo "Upload this folder: $OUT"
