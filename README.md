# OpenClaw Cloud Backup

**The cloud layer for OpenClaw's native backup.**

OpenClaw ships `openclaw backup create` — consistent SQLite snapshots,
volatile-file filtering, an embedded manifest, multi-directory coverage
(state, config, credentials, workspaces). This skill wraps it and adds what
the native command doesn't do: **GPG encryption, S3-compatible upload,
retention, verification, lean scope filtering, and staged restores** — with
an agent UX designed so you always know what is about to happen before it
does.

**Providers:** AWS S3, Cloudflare R2, Backblaze B2, DigitalOcean Spaces,
MinIO — anything with an S3-compatible API.

## Quick start

```
clawhub install cloud-backup
```

Then ask your OpenClaw agent:

> "Set up cloud backups for OpenClaw"

The agent walks the guided setup (provider → least-privilege key → encryption
→ first backup). **Nothing is uploaded, scheduled, or written to config
without your explicit confirmation, and your secret values never need to
transit the chat.**

## Modes

| Mode | Includes | Excludes by default | Sensitivity |
|---|---|---|---|
| `backup full` (default) | config, credentials, secret stores, state + agent SQLite snapshots, agent memory, workspace, skills | session transcripts, codex caches/logs, tools/, media/, logs/, old backups | encryption forced |
| `backup full --everything` | all of the above PLUS transcripts and codex history | previous backup archives | encryption forced |
| `backup settings` | config, secret stores, credentials, auth files | everything else | always encrypted |
| `backup workspace` | workspace dirs (skills, memory files) | all state/config | encrypted by default |

Tune with `config.exclude` / `config.include` (state-relative globs).
Today's typical result: a lean `full` archive is **~10–20× smaller** than a
v1 full archive, because Codex log databases, caches, and session transcripts
stay out unless you ask for them.

## Commands

```
bash scripts/cloud-backup.sh <command>
```

| Command | Description |
|---|---|
| `backup [full\|settings\|workspace] [--everything] [--dry-run]` | Create, encrypt, upload, apply retention |
| `list` | Local + remote backups (flags failure debris) |
| `status` | Health: last backup, credential sources, sensitivity verdict, schedule |
| `verify [name\|--latest] [--deep]` | Checksum + decrypt + listing (+ native `openclaw backup verify`) |
| `restore <name> [--target DIR \| --in-place] [--only GLOB] [--dry-run]` | Staged restore by default |
| `prune [--dry-run]` | Retention + failure-debris cleanup, local and remote |
| `schedule` | Print the opt-in cron command — never creates anything |
| `setup` | Setup checklist + connection test — never writes config |

## Security model (the short version)

- **Credentials never live in OpenClaw config.** S3 keys go in an AWS named
  profile (or operator-managed env); the GPG passphrase goes in a chmod-600
  passphrase file. Why it matters: backups archive `openclaw.json` — a secret
  stored there would ride inside every archive. v1-style plaintext config
  still works but warns loudly; removed in v3.
- **Or hook into OpenClaw's own secret store.** `config.accessKeyRef` /
  `secretKeyRef` / `passphraseRef` accept OpenClaw SecretRefs resolved against
  your `.secrets.providers` (file stores, env, exec backends like 1Password)
  — one credential model for the whole instance.
- **Encryption is forced for sensitive scopes.** The script detects whether
  the archive would contain real secret material and refuses plaintext output
  for it.
- **No durable plaintext, ever.** Archives are built in a per-run mode-700
  staging dir, removed on any exit and swept after hard kills. The passphrase
  is passed to gpg over a file descriptor, never on a command line.
- **Verified end to end.** sha256 sidecars, decrypt-and-list check after
  encryption, HEAD size/sha check after upload, `verify --deep` runs the
  native `openclaw backup verify` on the decrypted archive.
- **Scheduling is strictly opt-in.** The skill prints the exact
  `openclaw cron add` command and creates nothing without your confirmation.
- **Restores are staged.** Default restore lands in a fresh directory with
  printed next steps; `--in-place` requires typed confirmation.

Details: [SECURITY.md](SECURITY.md) and `references/security.md`.

## Restore

```bash
bash scripts/cloud-backup.sh restore --latest --dry-run        # always look first
bash scripts/cloud-backup.sh restore --latest --target ~/restore-drill
# review, then rsync what you need into ~/.openclaw (gateway stopped)
```

Do a restore drill after setup and occasionally after — a backup you've never
restored is a hope, not a backup. v1 archives remain restorable.

## Scheduling

`schedule` prints the recommended job — **this is what your agent will
propose; it never creates it without you**:

```bash
openclaw cron add \
  --name cloud-backup-daily \
  --cron "0 2 * * *" --tz "<your-tz>" \
  --session isolated --wake now \
  --message "Unattended cloud-backup run (operator preconfirmed): use the cloud-backup skill to run 'backup full'. Report archive name, size, encrypted status, upload destination, and verification result. If anything fails, include the exact stderr. Do not restore, prune, change config, or create schedules." \
  --announce --best-effort-deliver
```

## Migrating from v1

v2 keeps reading v1 config keys (with deprecation warnings), keeps restoring
v1 archives, and renames `cleanup` → `prune`. The local archive store moves
out of `~/.openclaw/backups` to `~/.local/share/openclaw-backups` (so backups
stop swallowing older backups). Full guide:
[docs/MIGRATION-v1-to-v2.md](docs/MIGRATION-v1-to-v2.md).

## v1 security-scan findings → v2

v1.1.5 was flagged by ClawHub's scanners. v2.0.0 was redesigned around those
findings rather than patched over them:

| Finding | v2 answer |
|---|---|
| SQP-1: overly broad activation ("use when the user says backup") | Narrow description + explicit-intent gating + per-action confirmation gates in SKILL.md |
| SQP-2: daily cron created by default | Scheduling is strictly opt-in; the exact command is shown and confirmed; never re-offered |
| SQP-2: docs instructed plaintext keys in config | All six provider docs lead with bucket-scoped keys in AWS profiles; passphrase file/SecretRef; plaintext config deprecated with loud warnings |

Point-by-point detail: [SECURITY.md](SECURITY.md).

## License & contributions

Issues and PRs welcome: https://github.com/obuchowski/openclaw-cloud-backup
