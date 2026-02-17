---
name: cloud-backup
description: Back up and restore OpenClaw state. Creates local archives and uploads to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces). Use when the user says "backup", "back up", "make a backup", "restore", or anything about backing up OpenClaw.
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","jq","aws"]}}}
---

# OpenClaw Cloud Backup

Backs up OpenClaw state to a local archive and uploads it to cloud storage.

**Do not ask** what to back up, where to store it, or anything about destinations. Just follow the steps below.

## Backup procedure (follow every step)

### Step 1: Run the backup

```bash
bash "{baseDir}/scripts/cloud-backup.sh" backup full
```

Default mode is `full`. Only use `skills` or `settings` if the user specifically asks.

### Step 2: Check script output for warnings

Look at the script output. If it contains `WARN: Cloud storage is not configured`, go to **Step 3**. Otherwise go to **Step 4**.

### Step 3: Cloud not configured — ask user to set it up

Tell the user the backup was saved locally, then ask:

> "Cloud storage isn't configured yet — backups are local only. Want to set up cloud upload? I support AWS S3, Cloudflare R2, Backblaze B2, MinIO, and DigitalOcean Spaces."

- If user says yes → go to **Cloud setup** section below, then re-run the backup.
- If user says no / local-only → set `config.upload=false` via `gateway config.patch`. Done.

**Do not skip this step.** The skill is called cloud-backup — always offer cloud setup when it's missing.

### Step 4: Report result and offer scheduling

Report the backup paths from the script output to the user. Then check if a cron job already exists for cloud-backup:

```
Use the cron tool: action=list
```

If no cron job mentions `cloud-backup`, offer to create one:

> "Want me to schedule daily backups automatically (e.g. 2 AM)?"

If user agrees, create the cron job:

```json
{
  "schedule": { "kind": "cron", "expr": "0 2 * * *" },
  "payload": { "kind": "agentTurn", "message": "Run cloud-backup: backup full" },
  "sessionTarget": "isolated"
}
```

**Do not skip the scheduling offer on first backup.**

---

## Cloud setup

When the user agrees to configure cloud storage:

1. **Ask which provider**: AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, or other.
2. **Read the matching provider guide** from `references/providers/` — it has exact config keys, endpoint format, and credential steps.
3. **Collect and write config** via `gateway config.patch` — bucket, credentials, endpoint (if non-AWS).
4. **Run `status`** to verify connectivity, then re-run backup.

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
