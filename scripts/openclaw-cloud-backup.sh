#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="${OPENCLAW_BACKUP_CONFIG:-$HOME/.openclaw-cloud-backup.conf}"
LOCK_DIR="${TMPDIR:-/tmp}/openclaw-cloud-backup.lock"

COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_RESET=""

INCLUDE_PATHS=()
REMOTE_ARCHIVE_KEYS=()

init_colors() {
  if [ -t 1 ]; then
    COLOR_RED="$(printf '\033[0;31m')"
    COLOR_GREEN="$(printf '\033[0;32m')"
    COLOR_YELLOW="$(printf '\033[1;33m')"
    COLOR_BLUE="$(printf '\033[0;34m')"
    COLOR_RESET="$(printf '\033[0m')"
  fi
}

log_info() {
  printf "%s[INFO]%s %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_warn() {
  printf "%s[WARN]%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*"
}

log_error() {
  printf "%s[ERROR]%s %s\n" "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

usage() {
  cat <<EOF
OpenClaw Cloud Backup

Usage:
  $SCRIPT_NAME backup [full|skills|settings]
  $SCRIPT_NAME list
  $SCRIPT_NAME restore <backup-name> [--dry-run] [--yes]
  $SCRIPT_NAME cleanup
  $SCRIPT_NAME status
  $SCRIPT_NAME help

Environment:
  OPENCLAW_BACKUP_CONFIG  Override config path (default: ~/.openclaw-cloud-backup.conf)

Examples:
  $SCRIPT_NAME backup full
  $SCRIPT_NAME list
  $SCRIPT_NAME restore openclaw_full_20260217_030001_host.tar.gz --dry-run
  $SCRIPT_NAME cleanup
EOF
}

normalize_bool() {
  case "${1:-}" in
    1|[Tt][Rr][Uu][Ee]|[Yy]|[Yy][Ee][Ss]|[Oo][Nn])
      printf "true\n"
      ;;
    *)
      printf "false\n"
      ;;
  esac
}

sanitize_int_or_default() {
  local value="${1:-}"
  local fallback="${2:-0}"
  case "$value" in
    ''|*[!0-9]*)
      printf "%s\n" "$fallback"
      ;;
    *)
      printf "%s\n" "$value"
      ;;
  esac
}

require_bin() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    log_error "Missing required binary: $name"
    exit 1
  fi
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log_error "Another backup process appears to be running (lock: $LOCK_DIR)"
    exit 1
  fi
  trap release_lock EXIT INT TERM
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  else
    log_warn "Config file not found at $CONFIG_FILE. Using defaults where possible."
  fi

  SOURCE_ROOT="${SOURCE_ROOT:-$HOME/.openclaw}"
  LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-$HOME/openclaw-cloud-backups}"
  TMP_DIR="${TMP_DIR:-$HOME/.openclaw-cloud-backup/tmp}"
  REGION="${REGION:-us-east-1}"
  ENDPOINT="${ENDPOINT:-}"
  BUCKET="${BUCKET:-}"
  PREFIX="${PREFIX:-openclaw-backups/$(hostname -s 2>/dev/null || hostname)/}"
  AWS_PROFILE="${AWS_PROFILE:-}"
  UPLOAD="$(normalize_bool "${UPLOAD:-true}")"
  ENCRYPT="$(normalize_bool "${ENCRYPT:-false}")"
  RETENTION_COUNT="$(sanitize_int_or_default "${RETENTION_COUNT:-10}" "10")"
  RETENTION_DAYS="$(sanitize_int_or_default "${RETENTION_DAYS:-30}" "30")"
  GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"
  GPG_PASSPHRASE_FILE="${GPG_PASSPHRASE_FILE:-}"

  PREFIX="${PREFIX#/}"
  if [ -n "$PREFIX" ]; then
    case "$PREFIX" in
      */) ;;
      *) PREFIX="${PREFIX}/" ;;
    esac
  fi

  mkdir -p "$LOCAL_BACKUP_DIR" "$TMP_DIR"
}

export_aws_env_if_present() {
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    export AWS_ACCESS_KEY_ID
  fi
  if [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    export AWS_SECRET_ACCESS_KEY
  fi
  if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
    export AWS_SESSION_TOKEN
  fi
}

aws_cli() {
  local -a cmd
  cmd=(aws)

  if [ -n "$AWS_PROFILE" ]; then
    cmd+=(--profile "$AWS_PROFILE")
  fi
  if [ -n "$REGION" ]; then
    cmd+=(--region "$REGION")
  fi
  if [ -n "$ENDPOINT" ]; then
    cmd+=(--endpoint-url "$ENDPOINT")
  fi

  cmd+=("$@")
  "${cmd[@]}"
}

require_cloud_config() {
  if [ -z "$BUCKET" ]; then
    log_error "BUCKET is empty. Set BUCKET in $CONFIG_FILE."
    exit 1
  fi
}

checksum_create() {
  local file_path="$1"
  local file_dir file_name
  file_dir="$(dirname "$file_path")"
  file_name="$(basename "$file_path")"

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$file_dir" && sha256sum "$file_name" > "${file_name}.sha256")
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$file_dir" && shasum -a 256 "$file_name" > "${file_name}.sha256")
  else
    log_error "Need sha256sum or shasum for checksum operations."
    exit 1
  fi
}

checksum_verify() {
  local file_path="$1"
  local file_dir file_name
  local checksum_file="${file_path}.sha256"

  if [ ! -f "$checksum_file" ]; then
    log_error "Checksum file missing: $checksum_file"
    exit 1
  fi

  file_dir="$(dirname "$file_path")"
  file_name="$(basename "$file_path")"

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$file_dir" && sha256sum -c "${file_name}.sha256" >/dev/null)
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$file_dir" && shasum -a 256 -c "${file_name}.sha256" >/dev/null)
  else
    log_error "Need sha256sum or shasum for checksum verification."
    exit 1
  fi
}

encrypt_file() {
  local input_file="$1"
  local output_file="${input_file}.gpg"

  if [ -n "$GPG_PASSPHRASE_FILE" ]; then
    gpg --batch --yes --pinentry-mode loopback \
      --passphrase-file "$GPG_PASSPHRASE_FILE" \
      --symmetric --cipher-algo AES256 \
      -o "$output_file" "$input_file"
  elif [ -n "$GPG_PASSPHRASE" ]; then
    gpg --batch --yes --pinentry-mode loopback \
      --passphrase "$GPG_PASSPHRASE" \
      --symmetric --cipher-algo AES256 \
      -o "$output_file" "$input_file"
  else
    gpg --symmetric --cipher-algo AES256 -o "$output_file" "$input_file"
  fi

  printf "%s\n" "$output_file"
}

decrypt_file() {
  local input_file="$1"
  local output_file="${input_file%.gpg}"

  if [ -n "$GPG_PASSPHRASE_FILE" ]; then
    gpg --batch --yes --pinentry-mode loopback \
      --passphrase-file "$GPG_PASSPHRASE_FILE" \
      -o "$output_file" -d "$input_file"
  elif [ -n "$GPG_PASSPHRASE" ]; then
    gpg --batch --yes --pinentry-mode loopback \
      --passphrase "$GPG_PASSPHRASE" \
      -o "$output_file" -d "$input_file"
  else
    gpg -o "$output_file" -d "$input_file"
  fi

  printf "%s\n" "$output_file"
}

build_include_paths() {
  local mode="$1"
  local candidates=()
  local rel

  INCLUDE_PATHS=()

  case "$mode" in
    full)
      candidates=(
        "openclaw.json"
        "settings.json"
        "settings.local.json"
        "projects.json"
        "skills"
        "commands"
        "mcp"
        "contexts"
        "templates"
        "modules"
        "workspace"
      )
      ;;
    skills)
      candidates=("skills" "commands")
      ;;
    settings)
      candidates=("openclaw.json" "settings.json" "settings.local.json" "projects.json" "mcp")
      ;;
    *)
      log_error "Invalid backup mode: $mode"
      exit 1
      ;;
  esac

  for rel in "${candidates[@]}"; do
    if [ -e "$SOURCE_ROOT/$rel" ]; then
      INCLUDE_PATHS+=("$rel")
    fi
  done

  if [ "${#INCLUDE_PATHS[@]}" -eq 0 ]; then
    log_error "No files found to back up under $SOURCE_ROOT for mode '$mode'."
    exit 1
  fi
}

create_archive() {
  local mode="$1"
  local timestamp host archive_name archive_path

  timestamp="$(date +%Y%m%d_%H%M%S)"
  host="$(hostname -s 2>/dev/null || hostname)"
  host="$(printf "%s" "$host" | tr -c '[:alnum:]._-' '_')"

  archive_name="openclaw_${mode}_${timestamp}_${host}.tar.gz"
  archive_path="$LOCAL_BACKUP_DIR/$archive_name"

  tar -czf "$archive_path" -C "$SOURCE_ROOT" "${INCLUDE_PATHS[@]}"
  printf "%s\n" "$archive_path"
}

upload_artifact() {
  local artifact_path="$1"
  local object_name object_key

  object_name="$(basename "$artifact_path")"
  object_key="${PREFIX}${object_name}"

  export_aws_env_if_present
  aws_cli s3 cp "$artifact_path" "s3://$BUCKET/$object_key"
  aws_cli s3 cp "${artifact_path}.sha256" "s3://$BUCKET/$object_key.sha256"
}

cmd_backup() {
  local mode="${1:-full}"
  local archive_path payload_path

  case "$mode" in
    full|skills|settings) ;;
    *)
      log_error "backup mode must be one of: full, skills, settings"
      exit 1
      ;;
  esac

  acquire_lock
  require_bin tar

  if [ ! -d "$SOURCE_ROOT" ]; then
    log_error "SOURCE_ROOT does not exist: $SOURCE_ROOT"
    exit 1
  fi

  build_include_paths "$mode"
  log_info "Creating $mode backup from $SOURCE_ROOT"
  for path in "${INCLUDE_PATHS[@]}"; do
    printf "  - %s\n" "$path"
  done

  archive_path="$(create_archive "$mode")"
  payload_path="$archive_path"

  if [ "$ENCRYPT" = "true" ]; then
    require_bin gpg
    log_info "Encrypting archive with GPG"
    payload_path="$(encrypt_file "$archive_path")"
  fi

  checksum_create "$payload_path"

  if [ "$UPLOAD" = "true" ]; then
    require_bin aws
    require_cloud_config
    log_info "Uploading backup to s3://$BUCKET/$PREFIX"
    upload_artifact "$payload_path"
    log_info "Upload complete"
  else
    log_warn "UPLOAD=false, cloud upload skipped."
  fi

  log_info "Backup created: $payload_path"
  log_info "Checksum: ${payload_path}.sha256"
}

cmd_list() {
  require_bin aws
  require_cloud_config
  export_aws_env_if_present

  log_info "Listing backups under s3://$BUCKET/$PREFIX"
  aws_cli s3 ls "s3://$BUCKET/$PREFIX" --recursive
}

extract_timestamp_from_key() {
  local key="$1"
  local base
  base="$(basename "$key")"

  printf "%s\n" "$base" | sed -n 's/.*_\([0-9]\{8\}_[0-9]\{6\}\)_.*/\1/p'
}

is_timestamp_older_than_days() {
  local timestamp="$1"
  local days="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    printf "0\n"
    return 0
  fi

  python3 - "$timestamp" "$days" <<'PY'
from datetime import datetime, timedelta
import sys

stamp = sys.argv[1]
days = int(sys.argv[2])

try:
    dt = datetime.strptime(stamp, "%Y%m%d_%H%M%S")
except ValueError:
    print("0")
    raise SystemExit(0)

cutoff = datetime.now() - timedelta(days=days)
print("1" if dt < cutoff else "0")
PY
}

delete_remote_archive_and_checksum() {
  local key="$1"
  aws_cli s3 rm "s3://$BUCKET/$key"
  aws_cli s3 rm "s3://$BUCKET/$key.sha256" >/dev/null 2>&1 || true
}

fetch_remote_archive_keys() {
  local list_file key
  REMOTE_ARCHIVE_KEYS=()

  list_file="$TMP_DIR/remote-listing-$$.txt"
  aws_cli s3 ls "s3://$BUCKET/$PREFIX" --recursive > "$list_file"

  while IFS= read -r line; do
    key="$(printf "%s\n" "$line" | awk '{print $4}')"
    if [ -z "$key" ]; then
      continue
    fi

    case "$key" in
      *.tar.gz|*.tar.gz.gpg)
        REMOTE_ARCHIVE_KEYS+=("$key")
        ;;
      *)
        ;;
    esac
  done < "$list_file"

  rm -f "$list_file"

  if [ "${#REMOTE_ARCHIVE_KEYS[@]}" -gt 0 ]; then
    IFS=$'\n' REMOTE_ARCHIVE_KEYS=($(printf "%s\n" "${REMOTE_ARCHIVE_KEYS[@]}" | sort))
    unset IFS
  fi
}

cmd_cleanup() {
  local total to_delete i key ts older deleted_count start_index

  acquire_lock
  require_bin aws
  require_cloud_config
  export_aws_env_if_present

  fetch_remote_archive_keys
  total="${#REMOTE_ARCHIVE_KEYS[@]}"
  deleted_count=0
  start_index=0

  if [ "$total" -eq 0 ]; then
    log_info "No remote archives found to clean up."
    return 0
  fi

  log_info "Found $total remote archive(s)."

  if [ "$total" -gt "$RETENTION_COUNT" ]; then
    to_delete=$((total - RETENTION_COUNT))
    log_info "Deleting $to_delete archive(s) by RETENTION_COUNT=$RETENTION_COUNT"
    i=0
    while [ "$i" -lt "$to_delete" ]; do
      key="${REMOTE_ARCHIVE_KEYS[$i]}"
      delete_remote_archive_and_checksum "$key"
      deleted_count=$((deleted_count + 1))
      i=$((i + 1))
    done
    start_index="$to_delete"
  fi

  if [ "$RETENTION_DAYS" -gt 0 ]; then
    if ! command -v python3 >/dev/null 2>&1; then
      log_warn "python3 not found; skipping RETENTION_DAYS cleanup."
    else
      log_info "Applying RETENTION_DAYS=$RETENTION_DAYS"
      i="$start_index"
      while [ "$i" -lt "${#REMOTE_ARCHIVE_KEYS[@]}" ]; do
        key="${REMOTE_ARCHIVE_KEYS[$i]}"
        ts="$(extract_timestamp_from_key "$key")"
        if [ -z "$ts" ]; then
          i=$((i + 1))
          continue
        fi
        older="$(is_timestamp_older_than_days "$ts" "$RETENTION_DAYS")"
        if [ "$older" = "1" ]; then
          delete_remote_archive_and_checksum "$key"
          deleted_count=$((deleted_count + 1))
        fi
        i=$((i + 1))
      done
    fi
  fi

  log_info "Cleanup complete. Deleted $deleted_count remote artifact set(s)."
}

cmd_restore() {
  local backup_name="$1"
  local dry_run="${2:-false}"
  local assume_yes="${3:-false}"
  local key download_dir local_artifact local_extract_source answer

  acquire_lock
  require_bin aws
  require_bin tar
  require_cloud_config
  export_aws_env_if_present

  if [ -z "$backup_name" ]; then
    log_error "restore requires a backup name."
    exit 1
  fi

  if [ "${backup_name#*/}" = "$backup_name" ]; then
    key="${PREFIX}${backup_name}"
  else
    key="$backup_name"
  fi

  download_dir="$TMP_DIR/restore-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$download_dir"

  local_artifact="$download_dir/$(basename "$key")"
  log_info "Downloading s3://$BUCKET/$key"
  aws_cli s3 cp "s3://$BUCKET/$key" "$local_artifact"
  aws_cli s3 cp "s3://$BUCKET/$key.sha256" "${local_artifact}.sha256"

  log_info "Verifying checksum"
  checksum_verify "$local_artifact"

  local_extract_source="$local_artifact"
  case "$local_artifact" in
    *.gpg)
      require_bin gpg
      log_info "Decrypting backup artifact"
      local_extract_source="$(decrypt_file "$local_artifact")"
      ;;
    *)
      ;;
  esac

  if [ "$dry_run" = "true" ]; then
    log_info "Dry-run mode: listing archive contents"
    tar -tzf "$local_extract_source"
    return 0
  fi

  if [ "$assume_yes" != "true" ]; then
    if [ -t 0 ]; then
      printf "%sThis will overwrite files in %s. Continue? (y/N): %s" "$COLOR_YELLOW" "$SOURCE_ROOT" "$COLOR_RESET"
      read -r answer
      case "$answer" in
        [Yy]|[Yy][Ee][Ss]) ;;
        *)
          log_warn "Restore cancelled."
          return 0
          ;;
      esac
    else
      log_error "Non-interactive restore requires --yes"
      exit 1
    fi
  fi

  mkdir -p "$SOURCE_ROOT"
  tar -xzf "$local_extract_source" -C "$SOURCE_ROOT"
  log_info "Restore complete into $SOURCE_ROOT"
}

cmd_status() {
  local missing=0

  printf "%sOpenClaw Cloud Backup status%s\n" "$COLOR_BLUE" "$COLOR_RESET"
  printf "Config file: %s\n" "$CONFIG_FILE"
  printf "SOURCE_ROOT: %s\n" "$SOURCE_ROOT"
  printf "LOCAL_BACKUP_DIR: %s\n" "$LOCAL_BACKUP_DIR"
  printf "TMP_DIR: %s\n" "$TMP_DIR"
  printf "UPLOAD: %s\n" "$UPLOAD"
  printf "ENCRYPT: %s\n" "$ENCRYPT"
  printf "BUCKET: %s\n" "${BUCKET:-<empty>}"
  printf "PREFIX: %s\n" "$PREFIX"
  printf "REGION: %s\n" "$REGION"
  printf "ENDPOINT: %s\n" "${ENDPOINT:-<aws-default>}"
  printf "RETENTION_COUNT: %s\n" "$RETENTION_COUNT"
  printf "RETENTION_DAYS: %s\n" "$RETENTION_DAYS"

  for bin_name in bash tar aws; do
    if command -v "$bin_name" >/dev/null 2>&1; then
      printf "Binary %-8s: found\n" "$bin_name"
    else
      printf "Binary %-8s: missing\n" "$bin_name"
      missing=1
    fi
  done

  if [ "$ENCRYPT" = "true" ]; then
    if command -v gpg >/dev/null 2>&1; then
      printf "Binary %-8s: found (required by ENCRYPT=true)\n" "gpg"
    else
      printf "Binary %-8s: missing (required by ENCRYPT=true)\n" "gpg"
      missing=1
    fi
  fi

  if [ "$missing" -eq 1 ]; then
    log_warn "One or more required binaries are missing."
  fi
}

main() {
  local command="${1:-help}"

  init_colors
  load_config

  case "$command" in
    backup)
      shift
      cmd_backup "${1:-full}"
      ;;
    list)
      cmd_list
      ;;
    restore)
      shift
      if [ "$#" -lt 1 ]; then
        log_error "restore requires <backup-name>"
        usage
        exit 1
      fi
      backup_name="$1"
      shift

      dry_run_flag="false"
      yes_flag="false"
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --dry-run)
            dry_run_flag="true"
            ;;
          --yes)
            yes_flag="true"
            ;;
          *)
            log_error "Unknown restore option: $1"
            exit 1
            ;;
        esac
        shift
      done

      cmd_restore "$backup_name" "$dry_run_flag" "$yes_flag"
      ;;
    cleanup)
      cmd_cleanup
      ;;
    status)
      cmd_status
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      log_error "Unknown command: $command"
      usage
      exit 1
      ;;
  esac
}

main "$@"
