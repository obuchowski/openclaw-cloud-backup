---
name: cloud-backup
description: Back up and restore OpenClaw configuration to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces). Use for local backups, cloud upload, restore, and retention cleanup.
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq","aws"],"env":["AWS_ACCESS_KEY_ID","AWS_SECRET_ACCESS_KEY"]}}}
---

# OpenClaw Cloud Backup

Back up OpenClaw configuration locally, with optional sync to S3-compatible cloud storage.

## Requirements

**Local backups:**
- `bash`, `tar`, `jq`

**Cloud sync** (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces):
- `aws` CLI (v1 or v2) — required for upload/download/list/restore from cloud

**Optional:**
- `gpg` — for client-side encryption

## References

- `references/provider-setup.md` — endpoint, region, keys, and least-privilege setup per provider
- `references/security-troubleshooting.md` — security guardrails and common failure fixes

## Setup

All configuration lives in OpenClaw config (`~/.openclaw/openclaw.json`):

- Non-secrets under `skills.entries.cloud-backup.config.*`
- Secrets under `skills.entries.cloud-backup.env.*`

### Config keys (`config.*`)

| Key | Default | Description |
|-----|---------|-------------|
| `bucket` | *(required)* | S3 bucket name |
| `region` | `us-east-1` | AWS region |
| `endpoint` | *(none)* | Custom endpoint for non-AWS providers |
| `awsProfile` | *(none)* | Named AWS profile (alternative to keys) |
| `upload` | `true` | Upload to cloud after local backup |
| `encrypt` | `false` | Encrypt archives with GPG |
| `retentionCount` | `10` | Keep at least N backups |
| `retentionDays` | `30` | Delete backups older than N days |

### Env keys (`env.*`) — secrets

| Key | Description |
|-----|-------------|
| `AWS_ACCESS_KEY_ID` | Access key ID |
| `AWS_SECRET_ACCESS_KEY` | Secret access key |
| `AWS_SESSION_TOKEN` | Optional session token |
| `GPG_PASSPHRASE` | For client-side encryption |

### Derived automatically (no config needed)

| Value | Source |
|-------|--------|
| Source directory | `dirname` of OpenClaw config path (`~/.openclaw`) |
| Local backup dir | `<sourceRoot>/backups` |
| S3 prefix | `openclaw-backups/<hostname>/` |

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
```

### Verify setup

```bash
bash "{baseDir}/scripts/cloud-backup.sh" setup
bash "{baseDir}/scripts/cloud-backup.sh" status
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
