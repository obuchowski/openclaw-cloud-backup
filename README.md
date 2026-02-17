# OpenClaw Cloud Backup

Back up your OpenClaw configuration to local archives and any S3-compatible storage with a single Bash script.

Supported providers:

- AWS S3
- Cloudflare R2
- Backblaze B2 (S3 API)
- MinIO
- DigitalOcean Spaces
- Any other S3-compatible endpoint

## Goals

- Keep the implementation simple (no Node build step).
- Keep the workflow safe (checksums, lock, optional encryption).
- Keep docs practical (quick start in `SKILL.md`, deep details in `references/`).

## Repository Layout

```text
.
├── SKILL.md
├── README.md
├── example.conf
├── scripts/
│   └── openclaw-cloud-backup.sh
├── references/
│   ├── provider-setup.md
│   └── security-troubleshooting.md
└── publish-for-clawhub.sh
```

## Prerequisites

Required:

- `bash`
- `tar`
- `aws` CLI v2

Optional:

- `gpg` (if `ENCRYPT=true`)

Install AWS CLI:

- macOS (Homebrew): `brew install awscli`
- Linux: use your package manager or https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

## Quick Start

1. Copy and protect config:

   ```bash
   cp example.conf "$HOME/.openclaw-cloud-backup.conf"
   chmod 600 "$HOME/.openclaw-cloud-backup.conf"
   ```

2. Edit `~/.openclaw-cloud-backup.conf`:

   - Set `BUCKET`
   - Set `REGION`
   - Set `ENDPOINT` for non-AWS providers
   - Provide credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) or `AWS_PROFILE`

3. Run setup checks:

   ```bash
   bash scripts/openclaw-cloud-backup.sh status
   ```

4. Create first backup:

   ```bash
   bash scripts/openclaw-cloud-backup.sh backup full
   ```

5. Confirm in cloud:

   ```bash
   bash scripts/openclaw-cloud-backup.sh list
   ```

## Configuration

Default config path:

- `~/.openclaw-cloud-backup.conf`

Override config path:

```bash
OPENCLAW_BACKUP_CONFIG=/path/to/config.conf bash scripts/openclaw-cloud-backup.sh status
```

Main settings:

- `SOURCE_ROOT` - local OpenClaw folder to back up (default: `~/.openclaw`)
- `LOCAL_BACKUP_DIR` - local archive folder
- `BUCKET` - S3 bucket
- `PREFIX` - key prefix inside bucket
- `REGION` - AWS/S3 region
- `ENDPOINT` - required for non-AWS providers
- `UPLOAD` - `true` or `false`
- `ENCRYPT` - `true` or `false`
- `RETENTION_COUNT` and `RETENTION_DAYS` - cleanup rules

See `example.conf` for all options.

## Commands

### `backup [full|skills|settings]`

Creates a timestamped archive, writes SHA-256 checksum, optionally encrypts with GPG, then uploads to cloud (when `UPLOAD=true`).

Examples:

```bash
bash scripts/openclaw-cloud-backup.sh backup full
bash scripts/openclaw-cloud-backup.sh backup skills
bash scripts/openclaw-cloud-backup.sh backup settings
```

### `list`

Lists backup artifacts under `s3://$BUCKET/$PREFIX`.

```bash
bash scripts/openclaw-cloud-backup.sh list
```

### `restore <backup-name> [--dry-run] [--yes]`

Downloads archive and checksum from cloud, verifies checksum, optionally decrypts, then restores into `SOURCE_ROOT`.

```bash
bash scripts/openclaw-cloud-backup.sh restore openclaw_full_20260217_030001_host.tar.gz --dry-run
bash scripts/openclaw-cloud-backup.sh restore openclaw_full_20260217_030001_host.tar.gz --yes
```

### `cleanup`

Deletes old backups by count and (when possible) by age.

```bash
bash scripts/openclaw-cloud-backup.sh cleanup
```

### `status`

Prints effective config and dependency status.

```bash
bash scripts/openclaw-cloud-backup.sh status
```

## Provider Setup

Use `references/provider-setup.md` for exact provider steps, credential retrieval, and least-privilege guidance.

Minimum concept for any provider:

1. Create a private bucket.
2. Create key pair with read/write/list/delete limited to that bucket.
3. Set endpoint + region + credentials in config.
4. Test with `status`, then `backup full`.

## Restore Workflow

Safe restore flow:

1. `list` to find the backup name.
2. `restore <name> --dry-run` to inspect archive.
3. `restore <name> --yes` to apply.
4. Validate expected files in `SOURCE_ROOT`.

## Scheduling

### Cron (macOS/Linux)

Daily backup at 02:00:

```bash
0 2 * * * /usr/bin/env bash /absolute/path/to/scripts/openclaw-cloud-backup.sh backup full >> /tmp/openclaw-cloud-backup.log 2>&1
```

Weekly cleanup:

```bash
0 3 * * 0 /usr/bin/env bash /absolute/path/to/scripts/openclaw-cloud-backup.sh cleanup >> /tmp/openclaw-cloud-backup.log 2>&1
```

## Security Notes

- Backups may contain sensitive OpenClaw data.
- Always keep bucket private.
- Keep credentials in config (`chmod 600`) or secure env vars.
- Do not commit secret config files.
- Use `ENCRYPT=true` for client-side encryption when needed.
- Keep restore checksum verification enabled.

See `references/security-troubleshooting.md` for full guidance.

## ClawHub Publishing

This repo includes `publish-for-clawhub.sh` to build a clean upload folder:

```bash
bash publish-for-clawhub.sh
```

Output:

- `./clawhub-bundle/`

Then upload that folder in ClawHub.

## Troubleshooting

Common issues and fixes are documented in:

- `references/security-troubleshooting.md`

## License

MIT
