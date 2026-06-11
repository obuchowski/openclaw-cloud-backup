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
# Ship the remediation map and changelog with the package: the clawscan note
# references SECURITY.md, so the scanner must find it inside the bundle.
cp "$REPO_ROOT/SECURITY.md" "$OUT/"
cp "$REPO_ROOT/CHANGELOG.md" "$OUT/"

echo "Created: $OUT"
ls -R "$OUT"
echo ""
echo "Publish with:"
echo "  clawhub skill publish \"$OUT\" --slug cloud-backup --version <semver> \\"
echo "    --changelog \"\$(sed -n '/^## /,/^## /p' \"$REPO_ROOT/CHANGELOG.md\" | head -n -1)\" \\"
echo "    --clawscan-note 'v2.0.0 remediates the v1.1.5 findings point by point (see SECURITY.md): activation narrowed to explicit OpenClaw-backup intent with per-action confirmation gates (SQP-1); cron scheduling is strictly opt-in and never created by default (SQP-2); credentials move to AWS named profiles / passphrase files / OpenClaw SecretRefs and plaintext-in-config is deprecated with loud warnings (SQP-2). Network access is limited to the user-configured S3 endpoint via the aws CLI; gpg performs symmetric archive encryption; openclaw backup create/verify provide the archive engine.'"
