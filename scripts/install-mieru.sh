#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-H2Kimi7/wyx2685-v2board-mieru-patch}"
BRANCH="${BRANCH:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${REPO}/${BRANCH}}"
PATCH_URL="${PATCH_URL:-${RAW_BASE}/patches/wyx2685-mieru-support.patch}"
SUPPLEMENT_PATCH_URL="${SUPPLEMENT_PATCH_URL:-${RAW_BASE}/patches/wyx2685-mieru-frontend-supplement.patch}"
APP_DIR="${APP_DIR:-$(pwd)}"
BACKUP_ROOT="${BACKUP_ROOT:-}"
SKIP_DB="${SKIP_DB:-0}"
TMP_PATCH=""
TMP_SUPPLEMENT_PATCH=""

log() {
  printf '[mieru-patch] %s\n' "$*"
}

fail() {
  printf '[mieru-patch] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing command: $1"
  fi
}

trim_quotes() {
  local value="${1:-}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

env_value() {
  local key="$1"
  local file="$APP_DIR/.env"
  local line
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  line="${line#*=}"
  trim_quotes "$line"
}

detect_app_dir() {
  APP_DIR="$(cd "$APP_DIR" && pwd)"
  if [[ ! -f "$APP_DIR/artisan" || ! -d "$APP_DIR/app/Services" ]]; then
    fail "APP_DIR does not look like wyx2685-v2board. Run from project root or set APP_DIR=/path/to/v2board"
  fi
}

install_os_packages_if_needed() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v patch >/dev/null 2>&1 || missing+=("patch")
  if [[ "$SKIP_DB" != "1" ]]; then
    command -v php >/dev/null 2>&1 || missing+=("php-cli")
  fi
  if [[ "${#missing[@]}" -eq 0 ]]; then
    return
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "Missing packages: ${missing[*]}. Install them first or rerun as root."
  fi
  log "Installing missing packages: ${missing[*]}"
  apt-get update
  apt-get install -y "${missing[@]}"
}

download_patch() {
  local url="$1"
  local tmp_patch="$2"
  log "Downloading patch from ${url}"
  curl -fsSL "$url" -o "$tmp_patch"
  [[ -s "$tmp_patch" ]] || fail "Downloaded patch is empty"
}

backup_files() {
  local patch_file="$1"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -z "$BACKUP_ROOT" ]]; then
    BACKUP_ROOT="$APP_DIR/storage/backups/mieru-patch-${stamp}"
  fi
  mkdir -p "$BACKUP_ROOT"
  log "Backing up touched files to ${BACKUP_ROOT}"

  grep -E '^\+\+\+ ' "$patch_file" \
    | awk '{print $2}' \
    | grep -Ev '^/dev/null$' >/tmp/mieru-patch-files.$$

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ "$path" == *"1970-01-01"* ]]; then
      continue
    fi
    local src="$APP_DIR/$path"
    if [[ -f "$src" ]]; then
      mkdir -p "$BACKUP_ROOT/$(dirname "$path")"
      cp -a "$src" "$BACKUP_ROOT/$path"
    fi
  done </tmp/mieru-patch-files.$$
  rm -f /tmp/mieru-patch-files.$$
}

apply_patch_file() {
  local patch_file="$1"
  local label="$2"
  local allow_reversed_skip="${3:-0}"
  cd "$APP_DIR"
  if patch --dry-run -p0 < "$patch_file" >/tmp/mieru-patch-dry-run.log 2>&1; then
    log "Applying ${label}"
    patch -p0 < "$patch_file"
    return
  fi

  if [[ "$allow_reversed_skip" == "1" ]] && grep -q 'Reversed (or previously applied) patch detected' /tmp/mieru-patch-dry-run.log; then
    log "${label} appears to be already applied; skipping"
    return
  fi

  return 1
}

apply_code_patch() {
  local full_patch="$1"
  local supplement_patch="$2"
  if apply_patch_file "$full_patch" "full Mieru patch" 0; then
    return
  fi

  log "Full patch did not apply cleanly; trying frontend supplement for an existing backend-patched install"
  if apply_patch_file "$supplement_patch" "frontend supplement patch" 1; then
    return
  fi

  fail "Patch dry-run failed. Your local files may differ from the expected wyx2685 version."
}

run_database_migration() {
  if [[ "$SKIP_DB" == "1" ]]; then
    log "SKIP_DB=1, skipping database migration"
    return
  fi
  [[ -f "$APP_DIR/.env" ]] || fail ".env not found; cannot read database credentials"

  local db_host db_port db_name db_user db_pass
  db_host="$(env_value DB_HOST)"
  db_port="$(env_value DB_PORT)"
  db_name="$(env_value DB_DATABASE)"
  db_user="$(env_value DB_USERNAME)"
  db_pass="$(env_value DB_PASSWORD)"
  db_host="${db_host:-127.0.0.1}"
  db_port="${db_port:-3306}"

  [[ -n "$db_name" && -n "$db_user" ]] || fail "DB_DATABASE or DB_USERNAME is empty in .env"

  log "Creating v2_server_mieru table if missing"
  DB_HOST="$db_host" DB_PORT="$db_port" DB_DATABASE="$db_name" DB_USERNAME="$db_user" DB_PASSWORD="$db_pass" php <<'PHP'
<?php
$dsn = sprintf(
    'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
    getenv('DB_HOST'),
    getenv('DB_PORT'),
    getenv('DB_DATABASE')
);
$pdo = new PDO($dsn, getenv('DB_USERNAME'), getenv('DB_PASSWORD'), [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
]);
$pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS `v2_server_mieru` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `group_id` varchar(255) NOT NULL,
  `route_id` varchar(255) DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `parent_id` int(11) DEFAULT NULL,
  `host` varchar(255) NOT NULL,
  `port` varchar(11) NOT NULL,
  `server_port` int(11) NOT NULL,
  `tags` varchar(255) DEFAULT NULL,
  `rate` varchar(11) NOT NULL,
  `show` tinyint(1) NOT NULL DEFAULT '0',
  `sort` int(11) DEFAULT NULL,
  `transport` varchar(8) NOT NULL DEFAULT 'TCP',
  `traffic_pattern` varchar(255) DEFAULT NULL,
  `created_at` int(11) NOT NULL,
  `updated_at` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
SQL);
PHP
}

clear_cache() {
  cd "$APP_DIR"
  if [[ -f artisan ]] && command -v php >/dev/null 2>&1; then
    php artisan config:clear >/dev/null 2>&1 || true
    php artisan cache:clear >/dev/null 2>&1 || true
  fi
}

main() {
  detect_app_dir
  install_os_packages_if_needed
  require_cmd curl
  require_cmd patch
  if [[ "$SKIP_DB" != "1" ]]; then
    require_cmd php
  fi

  TMP_PATCH="$(mktemp)"
  TMP_SUPPLEMENT_PATCH="$(mktemp)"
  trap 'rm -f "$TMP_PATCH" "$TMP_SUPPLEMENT_PATCH" /tmp/mieru-patch-dry-run.log' EXIT

  download_patch "$PATCH_URL" "$TMP_PATCH"
  download_patch "$SUPPLEMENT_PATCH_URL" "$TMP_SUPPLEMENT_PATCH"
  backup_files "$TMP_PATCH"
  apply_code_patch "$TMP_PATCH" "$TMP_SUPPLEMENT_PATCH"
  run_database_migration
  clear_cache

  log "Done."
  log "Mieru admin API: /api/v1/{secure_path}/server/mieru/save"
  log "Mieru node API: /api/v1/server/uniproxy/config?node_type=mieru&node_id=ID&token=SERVER_TOKEN"
  log "Backup path: ${BACKUP_ROOT}"
  log "The compiled admin frontend has been patched to show Mieru in the node create menu."
}

main "$@"
