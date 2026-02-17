# OpenClaw Cloud Backup

Back up your OpenClaw configuration to local archives and any S3-compatible storage.

**Supported providers:** AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, any S3-compatible endpoint.

## Installation

Install as an OpenClaw skill from [ClawHub](https://clawhub.com) or copy the `clawhub-bundle/` contents to your skills directory.

## Prerequisites

- `bash`, `tar`, `jq`
- `aws` CLI v1 or v2 ([install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- `gpg` (optional, for encryption)

## Quick Start

### 1. Configure

Everything lives in OpenClaw config (`~/.openclaw/openclaw.json`).

**Ask your OpenClaw agent:**
> "Set up cloud-backup with bucket `my-bucket`, region `us-east-1`, access key `AKIA...` and secret `...`"

**Or manually:**
```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="my-bucket"'
openclaw config patch 'skills.entries.cloud-backup.config.region="us-east-1"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="AKIA..."'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="..."'

# Non-AWS providers — also set endpoint:
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://..."'
```

### 2. Verify

```bash
bash scripts/cloud-backup.sh setup
bash scripts/cloud-backup.sh status
```

### 3. First backup

```bash
bash scripts/cloud-backup.sh backup full
bash scripts/cloud-backup.sh list
```

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Show config guide and test connection |
| `status` | Print config and dependency status |
| `backup [full\|skills\|settings]` | Create and upload backup |
| `list` | List cloud backups |
| `restore <name> [--dry-run] [--yes]` | Download and restore |
| `cleanup` | Prune old backups |
| `help` | Show usage |

## Configuration

All settings live in `skills.entries.cloud-backup` in OpenClaw config.

### Non-secrets (`config.*`)

| Key | Default | Description |
|-----|---------|-------------|
| `bucket` | *(required)* | S3 bucket name |
| `region` | `us-east-1` | AWS region |
| `endpoint` | *(none)* | Custom endpoint for non-AWS providers |
| `awsProfile` | *(none)* | Named AWS profile (alternative to keys) |
| `upload` | `true` | Upload to cloud after backup |
| `encrypt` | `false` | GPG encrypt archives |
| `retentionCount` | `10` | Keep N most recent backups |
| `retentionDays` | `30` | Delete backups older than N days |

Source directory, local backup path, and S3 prefix are derived automatically from the OpenClaw config path and hostname — no configuration needed.

### Secrets (`env.*`)

| Key | Description |
|-----|-------------|
| `AWS_ACCESS_KEY_ID` | Access key ID |
| `AWS_SECRET_ACCESS_KEY` | Secret access key |
| `AWS_SESSION_TOKEN` | Optional session token |
| `GPG_PASSPHRASE` | For client-side encryption |

### Config priority

1. Environment variables (CI/automation override)
2. OpenClaw config (normal usage)

## Provider Setup

See `references/provider-setup.md` for provider-specific instructions.

## Scheduling

Use OpenClaw's native cron — ask your agent:

> "Schedule daily cloud backups at 2am"

> "Run weekly backup cleanup on Sundays"

The agent creates isolated cron jobs that invoke the backup script automatically.

## Security

- Keep bucket private with least-privilege credentials
- Secrets in OpenClaw config are protected by file permissions
- Archive paths are validated against traversal attacks
- Always `restore --dry-run` before extracting
- See `references/security-troubleshooting.md` for full guidance

## Repository Layout

```
├── SKILL.md                 # Skill definition (bundled)
├── README.md                # This file (GitHub only)
├── scripts/
│   └── cloud-backup.sh

├── references/
│   ├── provider-setup.md
│   └── security-troubleshooting.md
├── publish-for-clawhub.sh   # Build ClawHub bundle
└── clawhub-bundle/          # Generated upload folder
```

## ClawHub Publishing

```bash
bash publish-for-clawhub.sh
# Upload ./clawhub-bundle/ to ClawHub
```

## License

MIT
