---
name: openclaw-cloud-backup
description: Back up and restore OpenClaw configuration to S3-compatible cloud storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces). Use for local backups, cloud upload, restore, and retention cleanup.
metadata: {"openclaw":{"emoji":"☁️","requires":{"bins":["bash","tar","aws","jq"]}}}
---

# OpenClaw Cloud Backup

Back up OpenClaw configuration to any S3-compatible storage.

## Requirements

- **Binaries:** `bash`, `tar`, `aws` (AWS CLI v2), `jq`
- **Optional:** `gpg` (if encryption enabled)

## References

- `references/provider-setup.md` — endpoint, region, keys, and least-privilege setup per provider
- `references/security-troubleshooting.md` — security guardrails and common failure fixes

## Setup

Secrets are stored in OpenClaw config at `skills.openclaw-cloud-backup.*`:

```
bucket              - S3 bucket name (required)
region              - AWS region (default: us-east-1)
endpoint            - Custom endpoint for non-AWS providers
awsAccessKeyId      - Access key ID
awsSecretAccessKey  - Secret access key
awsProfile          - Named AWS profile (alternative to keys)
gpgPassphrase       - For client-side encryption (optional)
```

### Agent-assisted setup (recommended)

Tell the agent:
> "Set up openclaw-cloud-backup with bucket `my-backup-bucket`, region `us-east-1`, access key `AKIA...` and secret `...`"

The agent will run `gateway config.patch` to store credentials securely.

### Manual setup

```bash
# Store secrets in OpenClaw config
openclaw config patch 'skills.openclaw-cloud-backup.bucket="my-bucket"'
openclaw config patch 'skills.openclaw-cloud-backup.region="us-east-1"'
openclaw config patch 'skills.openclaw-cloud-backup.awsAccessKeyId="AKIA..."'
openclaw config patch 'skills.openclaw-cloud-backup.awsSecretAccessKey="..."'

# For non-AWS providers, also set endpoint:
openclaw config patch 'skills.openclaw-cloud-backup.endpoint="https://..."'
```

### Local settings (optional)

For non-secret settings (paths, retention), copy the example config:

```bash
cp "{baseDir}/example.conf" "$HOME/.openclaw-cloud-backup.conf"
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
5. Schedule periodic `backup` and `cleanup` as needed.
6. Restore with `restore <name> --dry-run` first, then without `--dry-run`.

## Config Priority

Settings are loaded in this order (first wins):

1. **Environment variables** — for CI/automation
2. **OpenClaw config** — `skills.openclaw-cloud-backup.*` (recommended)
3. **Local config file** — `~/.openclaw-cloud-backup.conf` (legacy/fallback)

## Security

- Keep bucket private and use least-privilege credentials.
- Secrets in OpenClaw config are protected by file permissions.
- Always run restore with `--dry-run` before extracting.
- Archive paths are validated to prevent traversal attacks.
- If credentials are compromised, rotate keys immediately.
