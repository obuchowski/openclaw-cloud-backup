# Security and Troubleshooting

## Security Baseline

1. Keep backup bucket private.
2. Use least-privilege credentials for one bucket only.
3. OpenClaw config file permissions protect secrets — ensure `~/.openclaw/openclaw.json` is readable only by your user.
4. Never commit credentials to git.
5. Rotate keys if you suspect leakage.

## Credential Handling

- Preferred:
  - `awsProfile` tied to a dedicated profile
  - or short-lived keys from your provider
- Avoid:
  - account-wide admin keys
  - sharing backup credentials between unrelated systems

## Encryption

Set `config.encrypt` to `true` to upload encrypted archives (`.gpg`).

For automation, set `env.GPG_PASSPHRASE` in OpenClaw config. If not set, gpg may prompt interactively.

## Integrity Verification

Each backup artifact has a `.sha256` checksum.

Restore flow verifies checksum before extraction. If checksum fails:

- stop restore immediately
- re-download backup
- check bucket/object consistency

## Restore Safety Checklist

Before restore:

1. Run dry-run:
   ```bash
   bash scripts/openclaw-cloud-backup.sh restore <backup-name> --dry-run
   ```
2. Confirm target directory (`sourceRoot`) is correct.
3. Confirm backup date and host are expected.
4. Take a fresh backup of current state if possible.

After restore:

1. Validate expected files under `sourceRoot`.
2. Confirm sensitive files still have correct permissions.
3. Run application smoke checks.

## Common Errors and Fixes

### `Unable to locate credentials`

- Check `skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are set.
- Re-run:
  ```bash
  bash scripts/openclaw-cloud-backup.sh status
  ```

### `AccessDenied` on upload/list/delete

- IAM/token permissions are too broad or too narrow.
- Ensure both bucket-level and object-level permissions exist.
- Verify bucket name is exact.

### `Invalid endpoint` / DNS errors

- Check `config.endpoint` format.
- Remove trailing spaces.
- For AWS S3, leave `endpoint` unset.

### Signature mismatch errors

- Region mismatch is common.
- Check `config.region` and provider docs.
- Verify system clock is correct.

### `gpg: command not found`

- Install gpg or set `config.encrypt` to `false`.

### Checksum verification failed

- Artifact may be incomplete or tampered.
- Re-run restore download.
- Validate you matched `.sha256` with the exact artifact name.

### Restore says archive not found

- Run `list` and copy exact object name.
- Include `.gpg` suffix if encrypted backups are used.

## Incident Response

If credentials are compromised:

1. Revoke key/token immediately in provider console.
2. Create new scoped credentials.
3. Update `skills.entries.cloud-backup.env.*` in OpenClaw config.
4. Review recent bucket objects and delete suspicious files.
5. Trigger a fresh backup with new credentials.
