---
name: cloud-backup
description: Back up and restore OpenClaw configuration to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces). Use for local backups, cloud upload, restore, and retention cleanup.
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq"]}}}
---

# OpenClaw Cloud Backup

Back up OpenClaw configuration locally, with optional sync to S3-compatible cloud storage.

## Requirements

**Local backups:**
- `bash`, `tar`, `jq`

**Cloud sync** (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces):
- `aws` CLI v2 — required for upload/download/list/restore from cloud

**Optional:**
- `gpg` — for client-side encryption

## References

- `references/provider-setup.md` — endpoint, region, keys, and least-privilege setup per provider
- `references/security-troubleshooting.md` — security guardrails and common failure fixes

## Setup

All configuration lives in OpenClaw config (`~/.openclaw/openclaw.json`):

- Non-secrets under `skills.entries.cloud-backup.config.*`
- Secrets under `skills.entries.cloud-backup.env.*`

### Config keys

| Key | Location | Default | Description |
|-----|----------|---------|-------------|
| `bucket` | `config` | *(required)* | S3 bucket name |
| `region` | `config` | `us-east-1` | AWS region |
| `endpoint` | `config` | *(none)* | Custom endpoint for non-AWS providers |
| `awsProfile` | `config` | *(none)* | Named AWS profile (alternative to keys) |
| `sourceRoot` | `config` | `~/.openclaw` | Directory to back up |
| `localBackupDir` | `config` | `~/openclaw-cloud-backups` | Where local archives are stored |
| `prefix` | `config` | `openclaw-backups/<hostname>/` | S3 key prefix (allows multi-device buckets) |
| `upload` | `config` | `true` | Upload to cloud after local backup |
| `encrypt` | `config` | `false` | Encrypt archives with GPG |
| `retentionCount` | `config` | `10` | Keep at least N backups |
| `retentionDays` | `config` | `30` | Delete backups older than N days |

### Env keys (secrets)

| Key | Location | Description |
|-----|----------|-------------|
| `AWS_ACCESS_KEY_ID` | `env` | Access key ID |
| `AWS_SECRET_ACCESS_KEY` | `env` | Secret access key |
| `AWS_SESSION_TOKEN` | `env` | Optional session token |
| `GPG_PASSPHRASE` | `env` | For client-side encryption |

### Agent-assisted setup (recommended)

Tell the agent:
> "Set up cloud-backup with bucket `my-backup-bucket`, region `us-east-1`, access key `AKIA...` and secret `...`"

The agent will run `gateway config.patch` to store credentials securely.

### Manual setup

```bash
# Cloud settings
openclaw config patch 'skills.entries.cloud-backup.config.bucket="my-bucket"'
openclaw config patch 'skills.entries.cloud-backup.config.region="us-east-1"'

# Secrets
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="AKIA..."'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="..."'

# Non-AWS providers — also set endpoint:
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://..."'

# Optional behavior overrides:
openclaw config patch 'skills.entries.cloud-backup.config.upload=false'
openclaw config patch 'skills.entries.cloud-backup.config.retentionCount=20'
```

### Verify setup

```bash
bash "{baseDir}/scripts/openclaw-cloud-backup.sh" setup
bash "{baseDir}/scripts/openclaw-cloud-backup.sh" status
```

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Show configuration guide and test connection |
| `status` | Print effective config and dependency status |
| `backup [full\|skills\|settings]` | Create and upload backup |
| `list` | List cloud backups |
| `restore <name> [--dry-run] [--yes]` | Download and restore backup |
| `cleanup` | Prune old backups by retention rules |

## Workflow

1. Run `setup` to configure credentials (via agent or manually).
2. Run `status` to verify everything is connected.
3. Run `backup full` for first backup.
4. Confirm with `list`.
5. Daily backups are scheduled automatically on first run (see Scheduling).
6. Restore with `restore <name> --dry-run` first, then without `--dry-run`.

## Scheduling

**Default: daily backups.** When running a backup and no cron job exists for this skill, automatically schedule a daily backup and notify the user. Example: "Backup complete. I've scheduled daily backups at 02:00 — let me know if you want a different schedule."

Use OpenClaw's native cron for automated backups. User can customize:

> "Schedule daily cloud backups at 2am"

> "Schedule weekly backup cleanup on Sundays at 3am"

The agent will create cron jobs that run the backup script. Example job configurations:

**Daily full backup at 02:00:**
```json
{
  "schedule": { "kind": "cron", "expr": "0 2 * * *" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: backup full" },
  "sessionTarget": "isolated"
}
```

**Weekly cleanup on Sunday at 03:00:**
```json
{
  "schedule": { "kind": "cron", "expr": "0 3 * * 0" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: cleanup" },
  "sessionTarget": "isolated"
}
```

For local-only backups, set `config.upload` to `false`.

## Security

- Keep bucket private and use least-privilege credentials.
- Secrets in OpenClaw config are protected by file permissions.
- Always run restore with `--dry-run` before extracting.
- Archive paths are validated to prevent traversal attacks.
- If credentials are compromised, rotate keys immediately.
