# OpenClaw Cloud Backup

Back up your OpenClaw configuration locally and to any S3-compatible storage.

**Supported providers:** AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces — anything with an S3-compatible API.

## Quick Start

### 1. Configure

Ask your OpenClaw agent:
> "Set up cloud-backup with Cloudflare R2, bucket `my-backups`, and these credentials..."

Or manually:
```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="my-backups"'
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://..."'  # non-AWS only
openclaw config patch 'skills.entries.cloud-backup.env.ACCESS_KEY_ID="..."'
openclaw config patch 'skills.entries.cloud-backup.env.SECRET_ACCESS_KEY="..."'
```

### 2. Verify and backup

```bash
bash scripts/cloud-backup.sh status
bash scripts/cloud-backup.sh backup full
bash scripts/cloud-backup.sh list
```

## Commands

| Command | Description |
|---------|-------------|
| `backup [full\|skills\|settings]` | Create and upload backup |
| `list` | List cloud backups |
| `restore <name> [--dry-run] [--yes]` | Download and restore |
| `cleanup` | Prune old backups |
| `status` | Show config and deps |
| `setup` | Setup guide + connection test |

## Configuration

All settings in `skills.entries.cloud-backup` in OpenClaw config (`~/.openclaw/openclaw.json`).

**Settings** (`config.*`): `bucket`, `region` (default: `us-east-1`), `endpoint`, `profile`, `upload` (default: `true`), `encrypt` (default: `false`), `retentionCount` (default: `10`), `retentionDays` (default: `30`).

**Secrets** (`env.*`): `ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`, `SESSION_TOKEN`, `GPG_PASSPHRASE`.

Only `bucket` + credentials are required. Everything else has sensible defaults.

## Provider Guides

- [AWS S3](references/providers/aws-s3.md)
- [Cloudflare R2](references/providers/cloudflare-r2.md)
- [Backblaze B2](references/providers/backblaze-b2.md)
- [MinIO](references/providers/minio.md)
- [DigitalOcean Spaces](references/providers/digitalocean-spaces.md)

## Prerequisites

- `bash`, `tar`, `jq`, `aws` CLI (v1 or v2)
- `gpg` (optional, for encryption)

## Repository Layout

```
├── SKILL.md                          # Skill definition
├── README.md
├── scripts/
│   └── cloud-backup.sh
├── references/
│   ├── security.md
│   └── providers/
│       ├── aws-s3.md
│       ├── cloudflare-r2.md
│       ├── backblaze-b2.md
│       ├── minio.md
│       └── digitalocean-spaces.md
└── publish-for-clawhub.sh
```

## License

MIT
