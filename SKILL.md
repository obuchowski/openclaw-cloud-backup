---
name: openclaw-cloud-backup
description: Back up and restore OpenClaw configuration to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces). Use for simple local backups, cloud upload, restore, and retention cleanup.
metadata: {"openclaw":{"requires":{"bins":["bash","tar","aws"],"config":["~/.openclaw-cloud-backup.conf"]}}}
---

# OpenClaw Cloud Backup

Simple, script-first backup skill for OpenClaw configuration plus S3-compatible cloud upload.

## References

- `references/provider-setup.md` - how to obtain endpoint, region, keys, and least-privilege access for each provider
- `references/security-troubleshooting.md` - security guardrails, checksum verification, and common failure fixes

## Quick Start

1. Create your local config:
   ```bash
   cp "{baseDir}/example.conf" "$HOME/.openclaw-cloud-backup.conf"
   chmod 600 "$HOME/.openclaw-cloud-backup.conf"
   ```
2. Edit `~/.openclaw-cloud-backup.conf` with your bucket, endpoint (if non-AWS), and credentials.
3. Run a first backup:
   ```bash
   bash "{baseDir}/scripts/openclaw-cloud-backup.sh" backup full
   ```
4. List cloud backups:
   ```bash
   bash "{baseDir}/scripts/openclaw-cloud-backup.sh" list
   ```

## Workflow

1. Validate setup with `status`.
2. Run `backup full` for complete backup or `backup skills` / `backup settings` for a smaller scope.
3. Confirm artifacts exist in cloud with `list`.
4. Run `cleanup` periodically to prune old backups.
5. Restore with `restore <backup-name> --dry-run` first, then run restore without dry-run.

## Commands

- `backup [full|skills|settings]`
- `list`
- `restore <backup-name> [--dry-run] [--yes]`
- `cleanup`
- `status`
- `help`

## Guardrails

- Keep bucket private and use least-privilege credentials only.
- Never commit `~/.openclaw-cloud-backup.conf`.
- Always run restore with `--dry-run` before extracting.
- Keep checksums enabled; do not restore if checksum validation fails.
- If credentials are compromised, rotate keys immediately and review uploaded files.
