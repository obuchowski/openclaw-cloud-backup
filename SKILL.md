---
name: cloud-backup
description: Back up and restore OpenClaw locally and to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces).
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq","aws"]}}}
---

# OpenClaw Cloud Backup

Back up `~/.openclaw` locally, with optional upload to any S3-compatible storage.

## Config

All settings live in `skills.entries.cloud-backup` in OpenClaw config.

### `config.*` — settings

| Key | Default | Required | Description |
|-----|---------|----------|-------------|
| `bucket` | — | for cloud | Storage bucket name |
| `region` | `us-east-1` | no | Region / location hint |
| `endpoint` | *(none)* | for non-AWS | S3-compatible endpoint URL |
| `profile` | *(none)* | no | Named AWS CLI profile (alternative to keys) |
| `upload` | `true` | no | Upload to cloud after local backup |
| `encrypt` | `false` | no | GPG-encrypt archives before upload |
| `retentionCount` | `10` | no | Keep at least N backups on cleanup |
| `retentionDays` | `30` | no | Delete backups older than N days on cleanup |

### `env.*` — secrets

| Key | Required | Description |
|-----|----------|-------------|
| `ACCESS_KEY_ID` | for cloud | S3-compatible access key |
| `SECRET_ACCESS_KEY` | for cloud | S3-compatible secret key |
| `SESSION_TOKEN` | no | Temporary session token |
| `GPG_PASSPHRASE` | no | For automated GPG encryption/decryption |

### Derived (no config needed)

- **Source dir**: `~/.openclaw` (dirname of config file)
- **Local backups**: `~/.openclaw/backups/`
- **S3 prefix**: `openclaw-backups/<hostname>/`

### Defaults behavior

The script applies defaults for any missing optional config. The agent does **not** need to write default values — only set what the user explicitly wants to change. Minimum config for cloud backups: `bucket` + credentials. Everything else just works.

## Commands

```
bash "{baseDir}/scripts/cloud-backup.sh" <command>
```

| Command | Description |
|---------|-------------|
| `backup [full\|skills\|settings]` | Create local archive; upload if `upload=true` |
| `list` | List remote backups |
| `restore <name> [--dry-run] [--yes]` | Download, verify, and extract a backup |
| `cleanup` | Prune old backups by retention rules |
| `status` | Show effective config and dependency check |
| `setup` | Interactive setup guide + connection test |

## Provider setup

See per-provider guides in `references/providers/`:

- `references/providers/aws-s3.md`
- `references/providers/cloudflare-r2.md`
- `references/providers/backblaze-b2.md`
- `references/providers/minio.md`
- `references/providers/digitalocean-spaces.md`

When the user asks to set up cloud backup, read the relevant provider guide for endpoint, region, and credential details.

## Scheduling

Use OpenClaw cron for automated backups:

**Daily full backup at 02:00:**
```json
{
  "schedule": { "kind": "cron", "expr": "0 2 * * *" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: backup full" },
  "sessionTarget": "isolated"
}
```

**Weekly cleanup (Sunday 03:00):**
```json
{
  "schedule": { "kind": "cron", "expr": "0 3 * * 0" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: cleanup" },
  "sessionTarget": "isolated"
}
```

After a successful first backup, offer to schedule daily backups if none exist.

## Security

- Secrets are stored in OpenClaw config, protected by file permissions.
- Archives are checksummed (SHA-256) and verified on restore.
- Tar paths are validated against traversal attacks.
- Always `restore --dry-run` before extracting.
- See `references/security.md` for credential handling and troubleshooting.
