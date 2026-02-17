#!/usr/bin/env bash
#
# OpenClaw Cloud Backup — back up ~/.openclaw to S3-compatible storage.
#
# Config lives in ~/.openclaw/openclaw.json under:
#   skills.entries.cloud-backup.config.*  (settings)
#   skills.entries.cloud-backup.env.*     (secrets)
#
# Usage: cloud-backup.sh <backup|list|restore|cleanup|status|setup|help>

set -euo pipefail

OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

# --- helpers ---

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ":: $*"; }
warn() { echo "WARN: $*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

need() {
  for bin in "$@"; do
    has "$bin" || die "missing required binary: $bin"
  done
}

# Read from openclaw config. Usage: cfg <section> <key>
#   cfg config bucket   → .skills.entries["cloud-backup"].config.bucket
#   cfg env AWS_ACCESS_KEY_ID → .skills.entries["cloud-backup"].env.AWS_ACCESS_KEY_ID
cfg() {
  has jq && [ -f "$OPENCLAW_CONFIG" ] || return 0
  jq -r ".skills.entries[\"cloud-backup\"].$1.$2 // empty" "$OPENCLAW_CONFIG" 2>/dev/null || true
}

# --- config ---

load_config() {
  BUCKET="$(cfg config bucket)"
  REGION="$(cfg config region)"
  REGION="${REGION:-us-east-1}"
  ENDPOINT="$(cfg config endpoint)"

  # Derived — no config keys needed
  SOURCE_ROOT="$(dirname "$OPENCLAW_CONFIG")"
  BACKUP_DIR="$SOURCE_ROOT/backups"
  TMP_DIR="$BACKUP_DIR/.tmp"
  PREFIX="openclaw-backups/$(hostname -s 2>/dev/null || hostname)/"

  # Behavior (defaults: upload=true, encrypt=false, keep 10 / 30 days)
  UPLOAD="$(cfg config upload)";           UPLOAD="${UPLOAD:-true}"
  ENCRYPT="$(cfg config encrypt)";         ENCRYPT="${ENCRYPT:-false}"
  RETENTION_COUNT="$(cfg config retentionCount)"; RETENTION_COUNT="${RETENTION_COUNT:-10}"
  RETENTION_DAYS="$(cfg config retentionDays)";   RETENTION_DAYS="${RETENTION_DAYS:-30}"

  # Credentials: env vars override config
  : "${AWS_ACCESS_KEY_ID:=$(cfg env AWS_ACCESS_KEY_ID)}"
  : "${AWS_SECRET_ACCESS_KEY:=$(cfg env AWS_SECRET_ACCESS_KEY)}"
  : "${AWS_SESSION_TOKEN:=$(cfg env AWS_SESSION_TOKEN)}"
  : "${AWS_PROFILE:=$(cfg config awsProfile)}"
  : "${GPG_PASSPHRASE:=$(cfg env GPG_PASSPHRASE)}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  mkdir -p "$BACKUP_DIR" "$TMP_DIR"
}

need_cloud() {
  [ -n "$BUCKET" ] || die "bucket not configured. Run: $(basename "$0") setup"
}

# Wrapper: aws with region/endpoint/profile flags.
s3() {
  local args=(aws)
  [ -n "$AWS_PROFILE" ] && args+=(--profile "$AWS_PROFILE")
  [ -n "$REGION" ]      && args+=(--region "$REGION")
  [ -n "$ENDPOINT" ]    && args+=(--endpoint-url "$ENDPOINT")
  "${args[@]}" s3 "$@"
}

# --- checksums ---

sha_cmd() {
  if has sha256sum; then echo sha256sum
  elif has shasum;  then echo "shasum -a 256"
  else die "need sha256sum or shasum"
  fi
}

checksum_create() {
  local dir; dir="$(dirname "$1")"
  local name; name="$(basename "$1")"
  (cd "$dir" && $(sha_cmd) "$name" > "$name.sha256")
}

checksum_verify() {
  [ -f "$1.sha256" ] || die "checksum file missing: $1.sha256"
  local dir; dir="$(dirname "$1")"
  local name; name="$(basename "$1")"
  (cd "$dir" && $(sha_cmd) -c "$name.sha256" >/dev/null) || die "checksum mismatch!"
}

# --- gpg ---

gpg_encrypt() {
  local out="$1.gpg"
  if [ -n "$GPG_PASSPHRASE" ]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
      --symmetric --cipher-algo AES256 -o "$out" "$1"
  else
    gpg --symmetric --cipher-algo AES256 -o "$out" "$1"
  fi
  echo "$out"
}

gpg_decrypt() {
  local out="${1%.gpg}"
  if [ -n "$GPG_PASSPHRASE" ]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
      -o "$out" -d "$1"
  else
    gpg -o "$out" -d "$1"
  fi
  echo "$out"
}

# --- tar safety ---

validate_tar() {
  local bad
  bad="$(tar -tzf "$1" 2>/dev/null | grep -E '^/|^\.\.(\/|$)|/\.\.(\/|$)' || true)"
  [ -z "$bad" ] || { echo "$bad" >&2; die "archive has unsafe paths"; }
}

# --- commands ---

cmd_backup() {
  local mode="${1:-full}"
  case "$mode" in full|skills|settings) ;; *) die "mode must be: full, skills, settings" ;; esac

  need tar
  [ -d "$SOURCE_ROOT" ] || die "source dir missing: $SOURCE_ROOT"

  # Pick what to include
  local -a candidates paths=()
  case "$mode" in
    full)     candidates=(openclaw.json settings.json settings.local.json projects.json skills commands mcp contexts templates modules workspace) ;;
    skills)   candidates=(skills commands) ;;
    settings) candidates=(openclaw.json settings.json settings.local.json projects.json mcp) ;;
  esac
  for c in "${candidates[@]}"; do
    [ -e "$SOURCE_ROOT/$c" ] && paths+=("$c")
  done
  [ ${#paths[@]} -gt 0 ] || die "nothing to back up in $SOURCE_ROOT ($mode)"

  info "Creating $mode backup (${#paths[@]} items)"

  local ts host archive
  ts="$(date +%Y%m%d_%H%M%S)"
  host="$(hostname -s 2>/dev/null || hostname)"
  archive="$BACKUP_DIR/openclaw_${mode}_${ts}_${host//[^a-zA-Z0-9._-]/_}.tar.gz"

  tar -czf "$archive" -C "$SOURCE_ROOT" "${paths[@]}"
  local payload="$archive"

  if [ "$ENCRYPT" = "true" ]; then
    need gpg
    info "Encrypting"
    payload="$(gpg_encrypt "$archive")"
  fi

  checksum_create "$payload"

  if [ "$UPLOAD" = "true" ]; then
    need aws; need_cloud
    info "Uploading to s3://$BUCKET/$PREFIX"
    s3 cp "$payload" "s3://$BUCKET/$PREFIX$(basename "$payload")"
    s3 cp "$payload.sha256" "s3://$BUCKET/$PREFIX$(basename "$payload").sha256"
  fi

  info "Done: $payload"
}

cmd_list() {
  need aws; need_cloud
  s3 ls "s3://$BUCKET/$PREFIX" --recursive
}

cmd_cleanup() {
  need aws; need_cloud

  # List remote archives (sorted by name = sorted by timestamp)
  local tmp="$TMP_DIR/listing-$$.txt"
  s3 ls "s3://$BUCKET/$PREFIX" --recursive > "$tmp"

  local -a keys=()
  while read -r _ _ _ key; do
    case "$key" in *.tar.gz|*.tar.gz.gpg) keys+=("$key") ;; esac
  done < "$tmp"
  rm -f "$tmp"

  local total=${#keys[@]} deleted=0
  [ "$total" -eq 0 ] && { info "No archives to clean up."; return; }
  info "Found $total archive(s)"

  # By count: keep newest RETENTION_COUNT
  if [ "$total" -gt "$RETENTION_COUNT" ]; then
    local excess=$((total - RETENTION_COUNT))
    info "Pruning $excess by count (keep $RETENTION_COUNT)"
    for ((i=0; i<excess; i++)); do
      s3 rm "s3://$BUCKET/${keys[$i]}"
      s3 rm "s3://$BUCKET/${keys[$i]}.sha256" 2>/dev/null || true
      ((deleted++))
    done
  fi

  # By age: delete older than RETENTION_DAYS
  if [ "$RETENTION_DAYS" -gt 0 ] && has date; then
    local cutoff
    # GNU date vs BSD date
    if date -d "now" >/dev/null 2>&1; then
      cutoff="$(date -d "$RETENTION_DAYS days ago" +%Y%m%d%H%M%S)"
    elif date -v-1d >/dev/null 2>&1; then
      cutoff="$(date -v-${RETENTION_DAYS}d +%Y%m%d%H%M%S)"
    else
      warn "Can't compute date cutoff; skipping age cleanup"; cutoff=""
    fi

    if [ -n "$cutoff" ]; then
      for key in "${keys[@]}"; do
        local ts
        ts="$(basename "$key" | sed -n 's/.*_\([0-9]\{8\}_[0-9]\{6\}\)_.*/\1/p' | tr -d _)"
        [ -n "$ts" ] || continue
        if [ "$ts" -lt "$cutoff" ]; then
          s3 rm "s3://$BUCKET/$key"
          s3 rm "s3://$BUCKET/$key.sha256" 2>/dev/null || true
          ((deleted++))
        fi
      done
    fi
  fi

  info "Cleanup done. Deleted $deleted."
}

cmd_restore() {
  local name="$1" dry_run="$2" yes="$3"
  [ -n "$name" ] || die "restore needs a backup name (run 'list' first)"

  need aws tar; need_cloud

  # If just a filename, prepend prefix
  local key="$name"
  [[ "$key" == */* ]] || key="${PREFIX}${key}"

  local dir="$TMP_DIR/restore-$$"
  mkdir -p "$dir"

  local file="$dir/$(basename "$key")"
  info "Downloading s3://$BUCKET/$key"
  s3 cp "s3://$BUCKET/$key" "$file"
  s3 cp "s3://$BUCKET/$key.sha256" "$file.sha256"

  checksum_verify "$file"

  # Decrypt if needed
  local src="$file"
  case "$file" in *.gpg) need gpg; info "Decrypting"; src="$(gpg_decrypt "$file")" ;; esac

  validate_tar "$src"

  if [ "$dry_run" = "true" ]; then
    info "Dry run — archive contents:"
    tar -tzf "$src"
    return
  fi

  if [ "$yes" != "true" ]; then
    if [ -t 0 ]; then
      printf "This will overwrite files in %s. Continue? [y/N] " "$SOURCE_ROOT"
      read -r ans
      case "$ans" in [Yy]*) ;; *) info "Cancelled."; return ;; esac
    else
      die "non-interactive restore needs --yes"
    fi
  fi

  tar -xzf "$src" -C "$SOURCE_ROOT" --no-same-owner --no-same-permissions
  info "Restored to $SOURCE_ROOT"
}

cmd_status() {
  echo "OpenClaw Cloud Backup"
  echo ""
  echo "Config: $OPENCLAW_CONFIG"
  echo ""
  echo "Cloud:"
  echo "  bucket:   ${BUCKET:-<not set>}"
  echo "  region:   $REGION"
  echo "  endpoint: ${ENDPOINT:-<aws default>}"
  echo "  prefix:   $PREFIX"
  echo ""
  echo "Credentials:"
  if [ -n "$AWS_PROFILE" ]; then
    echo "  AWS profile: $AWS_PROFILE"
  elif [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "  Access key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
  else
    echo "  <not configured>"
  fi
  echo ""
  echo "Paths:"
  echo "  source:  $SOURCE_ROOT"
  echo "  backups: $BACKUP_DIR"
  echo ""
  echo "Settings:"
  echo "  upload=$UPLOAD  encrypt=$ENCRYPT  keep=$RETENTION_COUNT  days=$RETENTION_DAYS"
  echo ""
  echo "Binaries:"
  for b in bash tar jq aws gpg; do
    if has "$b"; then echo "  $b: $(command -v "$b")"
    else echo "  $b: not found"
    fi
  done
}

cmd_setup() {
  echo "OpenClaw Cloud Backup Setup"
  echo ""
  echo "All settings go in: $OPENCLAW_CONFIG"
  echo ""
  echo "Quick start — ask your agent:"
  echo '  "Set up cloud-backup with bucket X and these credentials..."'
  echo ""
  echo "Or manually:"
  echo '  openclaw config patch '\''skills.entries.cloud-backup.config.bucket="my-bucket"'\'''
  echo '  openclaw config patch '\''skills.entries.cloud-backup.config.region="us-east-1"'\'''
  echo '  openclaw config patch '\''skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="AKIA..."'\'''
  echo '  openclaw config patch '\''skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="..."'\'''
  echo ""
  echo "Non-AWS providers also need:"
  echo '  openclaw config patch '\''skills.entries.cloud-backup.config.endpoint="https://..."'\'''
  echo ""

  cmd_status
  echo ""

  # Connection test
  if [ -n "$BUCKET" ] && { [ -n "$AWS_ACCESS_KEY_ID" ] || [ -n "$AWS_PROFILE" ]; }; then
    echo "Testing connection..."
    if s3 ls "s3://$BUCKET/" --max-items 1 >/dev/null 2>&1; then
      echo "✓ Connected. Run: $(basename "$0") backup full"
    else
      echo "✗ Failed. Check credentials and bucket name."
    fi
  fi
}

# --- main ---

cmd="${1:-help}"; shift || true

load_config

case "$cmd" in
  backup)  cmd_backup "${1:-full}" ;;
  list)    cmd_list ;;
  cleanup) cmd_cleanup ;;
  restore)
    name="${1:-}"; shift || true
    dry=false; yes=false
    for arg in "$@"; do
      case "$arg" in --dry-run) dry=true ;; --yes) yes=true ;; *) die "unknown option: $arg" ;; esac
    done
    cmd_restore "$name" "$dry" "$yes"
    ;;
  status)  cmd_status ;;
  setup)   cmd_setup ;;
  help|-h|--help)
    echo "Usage: $(basename "$0") <backup|list|restore|cleanup|status|setup|help>"
    echo ""
    echo "  backup [full|skills|settings]     Create backup (default: full)"
    echo "  list                               List cloud backups"
    echo "  restore <name> [--dry-run] [--yes] Download and restore"
    echo "  cleanup                            Prune old backups"
    echo "  status                             Show config and deps"
    echo "  setup                              Setup guide + connection test"
    ;;
  *) die "unknown command: $cmd" ;;
esac
