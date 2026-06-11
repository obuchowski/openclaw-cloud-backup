# Migrating from v1.x to v2.0

v2 keeps your v1 config working (with deprecation warnings) and keeps v1
archives restorable. But to get what v2 is for — credentials out of
openclaw.json, forced encryption, lean archives — walk these steps once.

## TL;DR

```bash
# 1. Move S3 keys to an AWS profile (run yourself; not via agent chat)
aws configure --profile openclaw-backup
chmod 600 ~/.aws/credentials
openclaw config patch 'skills.entries.cloud-backup.config.profile="openclaw-backup"'

# 2. Move the passphrase to a file (or pick a NEW, stronger one — see below)
umask 077 && mkdir -p ~/.openclaw/credentials
openssl rand -base64 32 > ~/.openclaw/credentials/cloud-backup.passphrase
openclaw config patch 'skills.entries.cloud-backup.config.passphraseFile="~/.openclaw/credentials/cloud-backup.passphrase"'
#    → store a copy in your password manager NOW.
#    → if this is a NEW passphrase, ALSO store the old one, labeled with its
#      date range: existing .gpg archives still need it.

# 3. Remove the plaintext block and verify
openclaw config patch 'skills.entries.cloud-backup.env=null'
jq '.skills.entries["cloud-backup"]' ~/.openclaw/openclaw.json   # no "env" block left
bash scripts/cloud-backup.sh status                              # zero DEPRECATED warnings

# 4. First v2 backup + verification + drill
bash scripts/cloud-backup.sh backup full --dry-run
bash scripts/cloud-backup.sh backup full
bash scripts/cloud-backup.sh verify --latest --deep
bash scripts/cloud-backup.sh restore --latest --target /tmp/restore-drill --dry-run
```

## Rotate the old key (recommended, not optional in spirit)

Your v1 key lived in `openclaw.json`, and v1 archived that file into every
backup — treat the key as exposed. Rotate-first, revoke-last:

1. Create a NEW bucket-scoped key at your provider (old one stays valid).
2. Put the new key into the profile (step 1 above) and verify a backup.
3. Check the bucket for any plaintext `*.tar.gz` objects (failed v1 runs
   uploaded none, but check) and prune old archives that contain the old key.
4. Only then revoke the old key.

## What changed underneath

| v1 | v2 |
|---|---|
| Own `tar -czf` of the state dir | `openclaw backup create` (consistent SQLite snapshots, manifest) + lean filter |
| Local store `~/.openclaw/backups` (each full backup swallowed the previous ones!) | `~/.local/share/openclaw-backups` (`config.localDir`); `backups/**` permanently excluded |
| `encrypt` default false; failures stranded **unencrypted** tarballs on disk | `encrypt` default true; encryption forced for secret-bearing scopes; staging cleaned on any exit |
| Passphrase on the gpg command line (visible in `ps`) | Passphrase via file descriptor |
| `cleanup`; modes `full/workspace/skills/settings` | `prune`; modes `full[ --everything]/settings/workspace` (old names alias with warnings) |
| Retention pooled all modes together | Per-mode retention (count + days) |
| Restore extracted straight over live state | Staged restore by default; `--in-place` gated |
| Cron job created by default | Strictly opt-in (`schedule` prints the command) |

## Old archives and the legacy directory

- v1 archives (any mode) restore fine with v2 (`restore` auto-detects the
  flavor).
- `list` shows the legacy `~/.openclaw/backups` dir separately and flags
  **plaintext** archives and failure debris; `prune` deletes the debris.
  Move any encrypted archives you want to keep into the new `localDir`, then
  empty the legacy dir — new full backups exclude it either way.
- If you had failed v1 runs, you likely have unencrypted `*.tar.gz` files in
  the legacy dir containing your full state **including openclaw.json with
  your old keys** — delete them (`prune` will) and rotate (above).

## Scheduled jobs

v1 typically installed a daily cron job calling the script (sometimes via a
wrapper like `run-backup.sh` working around a v1 tar bug — that bug is gone).
Recreate the job cleanly:

```bash
openclaw cron list                  # find the old job id
openclaw cron rm <old-id>
bash scripts/cloud-backup.sh schedule   # prints the recommended v2 command
# run the printed `openclaw cron add ...` after adjusting time/tz/delivery
```
