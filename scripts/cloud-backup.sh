#!/usr/bin/env bash
#
# OpenClaw Cloud Backup — back up ~/.openclaw locally and optionally to S3-compatible storage.
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
# Handles booleans correctly (jq's // treats false as falsy, so we use if/then/else).
cfg() {
  has jq && [ -f "$OPENCLAW_CONFIG" ] || return 0
  jq -r ".skills.entries[\"cloud-backup\"].$1.$2 | if . == null then empty else tostring end" "$OPENCLAW_CONFIG" 2>/dev/null || true
}

# --- config ---

load_config() {
  # Cloud settings
  BUCKET="$(cfg config bucket)"
  REGION="$(cfg config region)";   REGION="${REGION:-us-east-1}"
  ENDPOINT="$(cfg config endpoint)"

  # Derived paths
  SOURCE_ROOT="$(dirname "$OPENCLAW_CONFIG")"
  BACKUP_DIR="$SOURCE_ROOT/backups"
  TMP_DIR="$BACKUP_DIR/.tmp"
  PREFIX="openclaw-backups/$(hostname -s 2>/dev/null || hostname)/"

  # Behavior
  UPLOAD="$(cfg config upload)";             UPLOAD="${UPLOAD:-true}"
  ENCRYPT="$(cfg config encrypt)";           ENCRYPT="${ENCRYPT:-false}"
  RETENTION_COUNT="$(cfg config retentionCount)"; RETENTION_COUNT="${RETENTION_COUNT:-10}"
  RETENTION_DAYS="$(cfg config retentionDays)";   RETENTION_DAYS="${RETENTION_DAYS:-30}"

  # Credentials: env vars override config
  : "${AWS_ACCESS_KEY_ID:=$(cfg env ACCESS_KEY_ID)}"
  : "${AWS_SECRET_ACCESS_KEY:=$(cfg env SECRET_ACCESS_KEY)}"
  : "${AWS_SESSION_TOKEN:=$(cfg env SESSION_TOKEN)}"
  : "${AWS_PROFILE:=$(cfg config profile)}"
  : "${GPG_PASSPHRASE:=$(cfg env GPG_PASSPHRASE)}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  # Determine if cloud is available
  CLOUD_READY=false
  if [ -n "$BUCKET" ] && { [ -n "$AWS_ACCESS_KEY_ID" ] || [ -n "$AWS_PROFILE" ]; } && has aws; then
    CLOUD_READY=true
  fi

  mkdir -p "$BACKUP_DIR" "$TMP_DIR"
}

need_cloud() {
  [ "$CLOUD_READY" = "true" ] || die "cloud not configured (need bucket + credentials + aws CLI). Run: $(basename "$0") setup"
}

# aws s3 wrapper with region/endpoint/profile flags
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
    if [ "$CLOUD_READY" = "true" ]; then
      info "Uploading to s3://$BUCKET/$PREFIX"
      s3 cp "$payload" "s3://$BUCKET/$PREFIX$(basename "$payload")"
      s3 cp "$payload.sha256" "s3://$BUCKET/$PREFIX$(basename "$payload").sha256"
    else
      warn "upload=true but cloud not configured — skipped. Local archive saved."
    fi
  fi

  info "Done: $payload"
}

cmd_list() {
  # List local backups
  info "Local backups in $BACKUP_DIR:"
  local count=0
  for f in "$BACKUP_DIR"/openclaw_*.tar.gz "$BACKUP_DIR"/openclaw_*.tar.gz.gpg; do
    [ -f "$f" ] || continue
    local size name
    size="$(du -h "$f" | cut -f1)"
    name="$(basename "$f")"
    echo "  $size  $name"
    ((count++))
  done
  [ "$count" -gt 0 ] || echo "  (none)"

  # List remote backups if cloud is configured
  if [ "$CLOUD_READY" = "true" ]; then
    echo ""
    info "Remote backups in s3://$BUCKET/$PREFIX:"
    s3 ls "s3://$BUCKET/$PREFIX" --recursive
  fi
}

# Compute age cutoff timestamp (YYYYMMDDHHMMSS) for retention days.
# Returns empty if date math isn't available.
age_cutoff() {
  local days="$1"
  [ "$days" -gt 0 ] 2>/dev/null || return 0
  if date -d "now" >/dev/null 2>&1; then
    date -d "$days days ago" +%Y%m%d%H%M%S
  elif date -v-1d >/dev/null 2>&1; then
    date -v-${days}d +%Y%m%d%H%M%S
  fi
}

# Extract timestamp from archive filename → YYYYMMDDHHMMSS
archive_ts() {
  basename "$1" | sed -n 's/.*_\([0-9]\{8\}_[0-9]\{6\}\)_.*/\1/p' | tr -d _
}

cmd_cleanup() {
  local deleted=0

  # --- Local cleanup ---
  local -a local_files=()
  for f in "$BACKUP_DIR"/openclaw_*.tar.gz "$BACKUP_DIR"/openclaw_*.tar.gz.gpg; do
    [ -f "$f" ] && local_files+=("$f")
  done

  if [ ${#local_files[@]} -gt 0 ]; then
    IFS=$'\n' local_files=($(printf "%s\n" "${local_files[@]}" | sort)); unset IFS

    # By count
    if [ ${#local_files[@]} -gt "$RETENTION_COUNT" ]; then
      local excess=$(( ${#local_files[@]} - RETENTION_COUNT ))
      info "Pruning $excess local archive(s) (keep $RETENTION_COUNT)"
      for ((i=0; i<excess; i++)); do
        rm -f "${local_files[$i]}" "${local_files[$i]}.sha256"
        deleted=$((deleted + 1))
      done
    fi

    # By age
    local cutoff
    cutoff="$(age_cutoff "$RETENTION_DAYS")"
    if [ -n "$cutoff" ]; then
      for f in "${local_files[@]}"; do
        [ -f "$f" ] || continue  # may have been deleted by count above
        local ts; ts="$(archive_ts "$f")"
        [ -n "$ts" ] || continue
        if [ "$ts" -lt "$cutoff" ]; then
          info "Removing old local: $(basename "$f")"
          rm -f "$f" "$f.sha256"
          deleted=$((deleted + 1))
        fi
      done
    fi
  fi

  # --- Remote cleanup ---
  if [ "$CLOUD_READY" = "true" ]; then
    local tmp="$TMP_DIR/listing-$$.txt"
    s3 ls "s3://$BUCKET/$PREFIX" --recursive > "$tmp"

    local -a keys=()
    while read -r _ _ _ key; do
      case "$key" in *.tar.gz|*.tar.gz.gpg) keys+=("$key") ;; esac
    done < "$tmp"
    rm -f "$tmp"

    local total=${#keys[@]}

    # By count
    if [ "$total" -gt "$RETENTION_COUNT" ]; then
      local excess=$((total - RETENTION_COUNT))
      info "Pruning $excess remote archive(s) (keep $RETENTION_COUNT)"
      for ((i=0; i<excess; i++)); do
        s3 rm "s3://$BUCKET/${keys[$i]}"
        s3 rm "s3://$BUCKET/${keys[$i]}.sha256" 2>/dev/null || true
        deleted=$((deleted + 1))
      done
    fi

    # By age
    local cutoff
    cutoff="$(age_cutoff "$RETENTION_DAYS")"
    if [ -n "$cutoff" ]; then
      for key in "${keys[@]}"; do
        local ts; ts="$(archive_ts "$key")"
        [ -n "$ts" ] || continue
        if [ "$ts" -lt "$cutoff" ]; then
          s3 rm "s3://$BUCKET/$key"
          s3 rm "s3://$BUCKET/$key.sha256" 2>/dev/null || true
          deleted=$((deleted + 1))
        fi
      done
    fi
  fi

  info "Cleanup done. Deleted $deleted."
}

cmd_restore() {
  local name="$1" dry_run="$2" yes="$3"
  [ -n "$name" ] || die "restore needs a backup name (run 'list' first)"

  need tar

  local src=""

  # Check local first
  if [ -f "$BACKUP_DIR/$name" ]; then
    src="$BACKUP_DIR/$name"
    info "Restoring from local: $src"
  elif [ "$CLOUD_READY" = "true" ]; then
    # Download from cloud
    local key="$name"
    [[ "$key" == */* ]] || key="${PREFIX}${key}"

    local dir="$TMP_DIR/restore-$$"
    mkdir -p "$dir"
    src="$dir/$(basename "$key")"

    info "Downloading s3://$BUCKET/$key"
    s3 cp "s3://$BUCKET/$key" "$src"
    s3 cp "s3://$BUCKET/$key.sha256" "$src.sha256"
    checksum_verify "$src"
  else
    die "backup '$name' not found locally and cloud is not configured"
  fi

  # Decrypt if needed
  local extract="$src"
  case "$src" in *.gpg) need gpg; info "Decrypting"; extract="$(gpg_decrypt "$src")" ;; esac

  validate_tar "$extract"

  if [ "$dry_run" = "true" ]; then
    info "Dry run — archive contents:"
    tar -tzf "$extract"
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

  tar -xzf "$extract" -C "$SOURCE_ROOT" --no-same-owner --no-same-permissions
  info "Restored to $SOURCE_ROOT"
}

cmd_status() {
  echo "OpenClaw Cloud Backup"
  echo ""
  echo "Config: $OPENCLAW_CONFIG"
  echo ""
  echo "Paths:"
  echo "  source:  $SOURCE_ROOT"
  echo "  backups: $BACKUP_DIR"
  echo ""
  echo "Settings:"
  echo "  upload=$UPLOAD  encrypt=$ENCRYPT  keep=$RETENTION_COUNT  days=$RETENTION_DAYS"

  if [ "$UPLOAD" = "true" ] || [ -n "$BUCKET" ]; then
    echo ""
    echo "Cloud:"
    echo "  bucket:   ${BUCKET:-<not set>}"
    echo "  region:   $REGION"
    echo "  endpoint: ${ENDPOINT:-<default>}"
    echo "  prefix:   $PREFIX"
    echo ""
    echo "Credentials:"
    if [ -n "$AWS_PROFILE" ]; then
      echo "  profile: $AWS_PROFILE"
    elif [ -n "$AWS_ACCESS_KEY_ID" ]; then
      echo "  access key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
    else
      echo "  <not configured>"
    fi
    echo ""
    echo "Cloud ready: $CLOUD_READY"
  else
    echo ""
    echo "Mode: local-only (upload=false)"
  fi

  echo ""
  echo "Binaries:"
  local bins=(bash tar jq)
  [ "$UPLOAD" = "true" ] || [ -n "$BUCKET" ] && bins+=(aws)
  [ "$ENCRYPT" = "true" ] && bins+=(gpg)
  for b in "${bins[@]}"; do
    if has "$b"; then echo "  $b: $(command -v "$b")"
    else echo "  $b: NOT FOUND"
    fi
  done
}

cmd_setup() {
  echo "OpenClaw Cloud Backup Setup"
  echo ""
  echo "All settings go in: $OPENCLAW_CONFIG"
  echo ""
  echo "Local-only (no cloud):"
  echo '  openclaw config patch '\''skills.entries.cloud-backup.config.upload=false'\'''
  echo "  That's it. Run: $(basename "$0") backup full"
  echo ""
  echo "With cloud upload — ask your agent:"
  echo '  "Set up cloud-backup with Cloudflare R2 (or AWS S3, etc.)"'
  echo ""
  echo "Or manually:"
  echo '  openclaw config patch '\''skills.entries.cloud-backup.config.bucket="my-bucket"'\'''
  echo '  openclaw config patch '\''skills.entries.cloud-backup.config.endpoint="https://..."'\''  # non-AWS only'
  echo '  openclaw config patch '\''skills.entries.cloud-backup.env.ACCESS_KEY_ID="..."'\'''
  echo '  openclaw config patch '\''skills.entries.cloud-backup.env.SECRET_ACCESS_KEY="..."'\'''
  echo ""

  cmd_status

  # Connection test if cloud is configured
  if [ "$CLOUD_READY" = "true" ]; then
    echo ""
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
    echo "  list                               List local (and cloud) backups"
    echo "  restore <name> [--dry-run] [--yes] Restore from local or cloud"
    echo "  cleanup                            Prune old backups"
    echo "  status                             Show config and deps"
    echo "  setup                              Setup guide + connection test"
    ;;
  *) die "unknown command: $cmd" ;;
esac
