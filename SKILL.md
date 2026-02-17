---
name: cloud-backup
description: Back up and restore OpenClaw locally and to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces).
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq","aws"]}}}
---

# OpenClaw Cloud Backup

Back up `~/.openclaw` to local archives, with optional upload to any S3-compatible storage. Works as a local-only backup tool when `upload=false`.

## First run (agent onboarding)

When the user asks to set up or use cloud-backup and no `bucket` is configured yet:

1. **Ask: local-only or cloud?** The script always creates local archives under `~/.openclaw/backups/`. Cloud upload is optional.
   - **Local-only**: set `config.upload=false`. No provider, credentials, or `aws` CLI needed. Skip to step 5.
   - **Cloud**: continue to step 2.
2. **Ask which provider**: AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, or something else. Don't guess — ask.
3. **Read the matching provider guide** from `references/providers/` — it has the exact config keys, endpoint format, and credential steps.
4. **Collect and write config** — bucket name, credentials, endpoint (if non-AWS). Write via `gateway config.patch`. Only set what they provided — don't write defaults.
5. **Test**: run `status`, then `backup full`.
6. **Offer to schedule daily backups** if the first backup succeeds.
7. **Offer to review defaults** (encrypt, retention) — only if they want to, don't dump the config table unprompted.

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
| `retentionCount` | `10` | no | Keep at least N backups on cleanup (cloud); local is capped at 7 |
| `retentionDays` | `30` | no | Delete remote backups older than N days on cleanup |

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

- `references/providers/aws-s3.md` — AWS S3
- `references/providers/cloudflare-r2.md` — Cloudflare R2
- `references/providers/backblaze-b2.md` — Backblaze B2
- `references/providers/minio.md` — MinIO (self-hosted)
- `references/providers/digitalocean-spaces.md` — DigitalOcean Spaces
- `references/providers/other.md` — any other S3-compatible service

When the user asks to set up cloud backup, read the matching provider guide. If their provider isn't listed, use `other.md` — it covers generic S3-compatible setup, endpoint discovery, and compatibility notes.

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
