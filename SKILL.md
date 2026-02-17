---
name: cloud-backup
description: Back up and restore OpenClaw state. Creates local archives and uploads to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces). Use when the user says "backup", "back up", "make a backup", "restore", or anything about backing up OpenClaw.
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq","aws"]}}}
---

# OpenClaw Cloud Backup

## What this does

Backs up OpenClaw state to a local archive and uploads it to cloud storage. Don't ask the user *what* to back up — just run it.

## How to run a backup

```bash
bash "{baseDir}/scripts/cloud-backup.sh" backup full
```

Default mode is `full`. Only use `skills` or `settings` if the user specifically asks.

**Do not ask** where to store it, what to back up, or anything about destinations. Just run the command.

### After backup completes

Report the output from the script. Then:

- **Cloud configured** → backup is local + uploaded. Done.
- **Cloud NOT configured** → backup is local only. Prompt the user: "Backup saved locally. Want to set up cloud storage so backups are also uploaded offsite? I support AWS S3, Cloudflare R2, Backblaze B2, MinIO, and DigitalOcean Spaces."
- **Cloud configured but upload failed** → report the error and the local backup path.

## Cloud setup

When the user agrees to set up cloud (either from the prompt above or explicitly):

1. **Ask which provider**: AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, or other.
2. **Read the matching provider guide** from `references/providers/` for endpoint, region, and credential details.
3. **Collect and write config** via `gateway config.patch` — bucket, credentials, endpoint (if non-AWS).
4. **Run `status`** to verify, then re-run backup.

If the user explicitly says they only want local backups, set `config.upload=false`.

## After first successful cloud backup

Offer to schedule daily backups if no cron job exists for this skill:

```json
{
  "schedule": { "kind": "cron", "expr": "0 2 * * *" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: backup full" },
  "sessionTarget": "isolated"
}
```

## Commands

```
bash "{baseDir}/scripts/cloud-backup.sh" <command>
```

| Command | What it does |
|---------|-------------|
| `backup [full\|skills\|settings]` | Create archive + upload if configured. Default: `full` |
| `list` | Show local + remote backups |
| `restore <name> [--dry-run] [--yes]` | Restore from local or cloud. Always `--dry-run` first |
| `cleanup` | Prune old archives (local: capped at 7; cloud: count + age) |
| `status` | Show current config and dependency check |

## Config reference

All in `skills.entries.cloud-backup` in OpenClaw config. **Don't write defaults — the script handles them.**

### `config.*`

| Key | Default | Description |
|-----|---------|-------------|
| `bucket` | — | Storage bucket name (required for cloud) |
| `region` | `us-east-1` | Region hint |
| `endpoint` | *(none)* | S3-compatible endpoint (required for non-AWS) |
| `profile` | *(none)* | Named AWS CLI profile (alternative to keys) |
| `upload` | `true` | Upload to cloud after backup |
| `encrypt` | `false` | GPG-encrypt archives |
| `retentionCount` | `10` | Cloud: keep N backups. Local: capped at 7 |
| `retentionDays` | `30` | Cloud only: delete archives older than N days |

### `env.*`

| Key | Description |
|-----|-------------|
| `ACCESS_KEY_ID` | S3-compatible access key |
| `SECRET_ACCESS_KEY` | S3-compatible secret key |
| `SESSION_TOKEN` | Optional temporary token |
| `GPG_PASSPHRASE` | For automated encryption/decryption |

## Provider guides

Read the relevant one only during setup:

- `references/providers/aws-s3.md`
- `references/providers/cloudflare-r2.md`
- `references/providers/backblaze-b2.md`
- `references/providers/minio.md`
- `references/providers/digitalocean-spaces.md`
- `references/providers/other.md` — any S3-compatible service

## Security

See `references/security.md` for credential handling and troubleshooting.
