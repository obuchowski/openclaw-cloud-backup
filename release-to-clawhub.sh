#!/usr/bin/env bash
# Release this repo to ClawHub under BOTH A/B slugs.
#
#   A: slug cloud-backup           name "Cloud Backup"                            (2.0.x line)
#   B: slug openclaw-cloud-backup  name "Cloud Backup [S3, R2, B2, MinIO & more]" (1.1.x line)
#
# Same bundle, two listings — an A/B test of slug/name discoverability.
# Each slug keeps its own version sequence, so both versions are explicit args.
#
# Usage:
#   ./release-to-clawhub.sh <version-A> <version-B>
#   ./release-to-clawhub.sh 2.0.2 1.1.4
#
# With no args, prints the currently published versions and the changelog
# version at HEAD, then exits without publishing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$REPO_ROOT/cloud-backup"

SLUG_A="cloud-backup"
NAME_A="Cloud Backup"
SLUG_B="openclaw-cloud-backup"
NAME_B="Cloud Backup [S3, R2, B2, MinIO & more]"

CLAWSCAN_NOTE='v2.0.0 remediates the v1.1.5 findings point by point (see SECURITY.md): activation narrowed to explicit OpenClaw-backup intent with per-action confirmation gates (SQP-1); cron scheduling is strictly opt-in and never created by default (SQP-2); credentials move to AWS named profiles / passphrase files / OpenClaw SecretRefs and plaintext-in-config is deprecated with loud warnings (SQP-2). Network access is limited to the user-configured S3 endpoint via the aws CLI; gpg performs symmetric archive encryption; openclaw backup create/verify provide the archive engine.'

changelog_version() {
  sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' "$REPO_ROOT/CHANGELOG.md" | head -1
}

# First "## x.y.z" section of CHANGELOG.md, without the trailing next header.
changelog_section() {
  awk '/^## /{n++} n==1' "$REPO_ROOT/CHANGELOG.md" | sed -e '$ { /^## /d }'
}

if [ $# -lt 2 ]; then
  echo "CHANGELOG.md HEAD version: $(changelog_version)"
  echo
  for slug in "$SLUG_A" "$SLUG_B"; do
    echo "--- published: $slug"
    clawhub inspect "$slug" 2>/dev/null | grep -E "^Latest:|^$slug|Moderation:" || echo "  (inspect failed)"
  done
  echo
  echo "Usage: $0 <version-A:$SLUG_A> <version-B:$SLUG_B>"
  exit 1
fi

VER_A="$1"
VER_B="$2"
CHANGELOG_TEXT="$(changelog_section)"

echo "== Bundle"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$REPO_ROOT/SKILL.md" "$OUT/"
cp -r "$REPO_ROOT/scripts" "$OUT/scripts"
cp -r "$REPO_ROOT/references" "$OUT/references"
# clawscan-note references SECURITY.md, so the scanner must find it in-bundle.
cp "$REPO_ROOT/SECURITY.md" "$OUT/"
cp "$REPO_ROOT/CHANGELOG.md" "$OUT/"
echo "Created: $OUT"

publish() {
  local slug="$1" name="$2" version="$3"
  echo
  echo "== Publish $slug@$version ($name)"
  clawhub skill publish "$OUT" \
    --slug "$slug" \
    --version "$version" \
    --name "$name" \
    --changelog "$CHANGELOG_TEXT" \
    --clawscan-note "$CLAWSCAN_NOTE"
}

publish "$SLUG_A" "$NAME_A" "$VER_A"
publish "$SLUG_B" "$NAME_B" "$VER_B"

echo
echo "== Verify"
for slug in "$SLUG_A" "$SLUG_B"; do
  echo "--- $slug"
  clawhub inspect "$slug" 2>/dev/null | grep -E "^Latest:|Moderation:" || true
done
