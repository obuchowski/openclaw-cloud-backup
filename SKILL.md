---
name: cloud-backup
description: Back up and restore the OpenClaw state directory (~/.openclaw). Creates local archives and optionally uploads to S3-compatible cloud storage. Use when the user says "backup", "back up", "make a backup", "restore", or anything about backing up OpenClaw.
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq","aws"]}}}
---

# OpenClaw Cloud Backup

## What this does

Backs up the OpenClaw state. That's it. Don't ask the user *what* to back up.

- **Local archive** is always created (path shown in script output)
- **Cloud upload** happens automatically if configured (bucket + credentials exist)
- **Default mode is `full`** — just run it. Only use `skills` or `settings` mode if the user specifically asks.

## How to run a backup

```bash
bash "{baseDir}/scripts/cloud-backup.sh" backup full
```

After it finishes, tell the user:
- "Backup saved to `~/.openclaw/backups/<filename>`"
- If cloud is configured: "Also uploaded to `s3://<bucket>/<prefix>`"
- If cloud is NOT configured: don't mention cloud at all

**Do not ask** where to store the backup. Do not ask what to back up. Do not offer choices about destinations. Just run it.

## First run (setup)

Only when `backup` fails because cloud isn't configured AND `upload=true` (default):

1. **Ask: local-only or cloud?**
   - **Local-only**: set `config.upload=false` via `gateway config.patch`. Done.
   - **Cloud**: ask which provider (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, or other).
2. **Read the matching provider guide** from `references/providers/` for endpoint, region, and credential details.
3. **Collect and write config** via `gateway config.patch` — bucket, credentials, endpoint (if non-AWS).
4. **Run the backup again.**
5. **Offer to schedule daily backups** if the first backup succeeds.

## Commands

```
bash "{baseDir}/scripts/cloud-backup.sh" <command>
```

| Command | What it does |
|---------|-------------|
| `backup [full\|skills\|settings]` | Create archive + upload if configured. Default: `full` |
| `list` | Show local archives + remote backups (if cloud configured) |
| `restore <name> [--dry-run] [--yes]` | Restore from local or cloud. Always `--dry-run` first |
| `cleanup` | Prune old archives (local: keep min(N, 7); cloud: count + age) |
| `status` | Show current config, paths, and dependency check |

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

## Scheduling

After first successful backup, offer to schedule daily backups:

```json
{
  "schedule": { "kind": "cron", "expr": "0 2 * * *" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: backup full" },
  "sessionTarget": "isolated"
}
```

## Security

See `references/security.md` for credential handling and troubleshooting.
