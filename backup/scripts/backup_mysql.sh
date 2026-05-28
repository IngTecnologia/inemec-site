#!/usr/bin/env bash
# Backup MySQL/MariaDB para inemec_site (piloto).
# Espejo conceptual del backup_postgres.sh canonico de los otros proyectos, pero usando
# mysqldump + mysqladmin ping. Mantiene mismo protocolo de alertas, rclone, retencion.
#
# Variables de entorno requeridas:
#   PROJECT_NAME, PROJECT_SLUG, DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
#
# Variables opcionales (con defaults):
#   DB_PORT (3306), BACKUP_INTERVAL (600), BACKUP_RETENTION_DAYS (30),
#   BACKUP_DESTINATIONS (sharepoint_jesus_corp), BACKUP_REMOTE_ROOT (Inemec.150/backups),
#   ALERT_EMAIL (vacio = sin alertas), ALERT_COOLDOWN_SECONDS (21600),
#   SMTP_HOST (smtp.office365.com), SMTP_PORT (587), SMTP_USER, SMTP_PASS

set -uo pipefail

# ====== Defaults ======
DB_PORT="${DB_PORT:-3306}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_DESTINATIONS="${BACKUP_DESTINATIONS:-sharepoint_jesus_corp}"
BACKUP_REMOTE_ROOT="${BACKUP_REMOTE_ROOT:-Inemec.150/backups}"
ALERT_COOLDOWN_SECONDS="${ALERT_COOLDOWN_SECONDS:-21600}"
SMTP_HOST="${SMTP_HOST:-smtp.office365.com}"
SMTP_PORT="${SMTP_PORT:-587}"

LOG_DIR="/app/logs"
LOG_FILE="$LOG_DIR/backup.log"
STATE_DIR="$LOG_DIR/.alert_state"
BACKUPS_DIR="/app/backups"
TEMP_DIR="/app/temp"
mkdir -p "$LOG_DIR" "$STATE_DIR" "$BACKUPS_DIR" "$TEMP_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

require_env() {
  local missing=()
  for v in PROJECT_NAME PROJECT_SLUG DB_HOST DB_USER DB_PASSWORD DB_NAME; do
    if [ -z "${!v:-}" ]; then missing+=("$v"); fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    log "ERROR: missing required env vars: ${missing[*]}"
    exit 1
  fi
}

# ====== SMTP alert helpers (curl + STARTTLS, no MTA needed) ======
send_alert() {
  local alert_type="$1"
  local subject="$2"
  local body="$3"

  [ -z "${ALERT_EMAIL:-}" ] && return 0
  [ -z "${SMTP_USER:-}" ] && return 0
  [ -z "${SMTP_PASS:-}" ] && return 0

  local state_file="$STATE_DIR/$alert_type"
  local now last
  now=$(date +%s)
  if [ -f "$state_file" ]; then
    last=$(cat "$state_file" 2>/dev/null || echo 0)
    if [ $(( now - last )) -lt "$ALERT_COOLDOWN_SECONDS" ]; then
      log "alert '$alert_type' in cooldown ($((now - last))s < ${ALERT_COOLDOWN_SECONDS}s), skipping"
      return 0
    fi
  fi

  local mail_file
  mail_file=$(mktemp)
  cat > "$mail_file" <<EOF
From: "${PROJECT_NAME} Backup" <${SMTP_USER}>
To: ${ALERT_EMAIL}
Subject: [${PROJECT_NAME} backup] ${subject}
Date: $(date -R)
Content-Type: text/plain; charset=UTF-8

${body}

-- Automated message from ${PROJECT_NAME} backup daemon
   Container: $(hostname)
   Time: $(date -Iseconds)
EOF

  if curl -sS -m 30 --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
      --ssl-reqd \
      --mail-from "${SMTP_USER}" \
      --mail-rcpt "${ALERT_EMAIL}" \
      --user "${SMTP_USER}:${SMTP_PASS}" \
      --upload-file "$mail_file" 2>>"$LOG_FILE"; then
    echo "$now" > "$state_file"
    log "alert sent: $alert_type -> $ALERT_EMAIL"
  else
    log "WARN: alert send failed ($alert_type)"
  fi
  rm -f "$mail_file"
}

clear_alert() {
  local alert_type="$1"
  rm -f "$STATE_DIR/$alert_type"
}

# ====== Backup cycle ======
run_cycle() {
  require_env

  local timestamp dump_file dump_path year_month remote_prefix
  timestamp=$(date '+%Y%m%d_%H%M%S')
  year_month=$(date '+%Y/%m')
  dump_file="${PROJECT_SLUG}_backup_${timestamp}.sql.gz"
  dump_path="${BACKUPS_DIR}/${dump_file}"

  log "=== Backup cycle ${timestamp} ==="

  # 1. DB reachable?
  if ! MYSQL_PWD="$DB_PASSWORD" mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --silent 2>>"$LOG_FILE"; then
    log "ERROR: DB ${DB_HOST}:${DB_PORT} not reachable"
    send_alert "db_unreachable" "DB no responde" "El backup no pudo conectar a ${DB_HOST}:${DB_PORT} como ${DB_USER}."
    return 1
  fi
  clear_alert "db_unreachable"

  # 2. mysqldump -> gzip
  log "Dumping ${DB_NAME} -> ${dump_path}"
  local tmp_dump="${TEMP_DIR}/dump_${timestamp}.sql"
  if ! MYSQL_PWD="$DB_PASSWORD" mysqldump \
        -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
        --single-transaction --quick --routines --triggers --events \
        --default-character-set=utf8mb4 \
        --databases "$DB_NAME" > "$tmp_dump" 2>>"$LOG_FILE"; then
    log "ERROR: mysqldump failed"
    rm -f "$tmp_dump"
    send_alert "dump_failed" "mysqldump fallo" "El dump de ${DB_NAME} fallo. Revisar ${LOG_FILE} en el contenedor."
    return 1
  fi
  clear_alert "dump_failed"

  if ! gzip -c "$tmp_dump" > "$dump_path"; then
    log "ERROR: gzip failed"
    rm -f "$tmp_dump" "$dump_path"
    send_alert "dump_failed" "gzip fallo" "Compresion del dump fallo."
    return 1
  fi
  rm -f "$tmp_dump"
  local size_local
  size_local=$(stat -c '%s' "$dump_path")
  log "Dump local OK: ${dump_path} (${size_local} bytes)"

  # 3. Upload to remote destinations
  local IFS_BAK="$IFS"
  IFS=',' read -ra dests <<< "$BACKUP_DESTINATIONS"
  IFS="$IFS_BAK"
  local total=${#dests[@]}
  local success=0
  for dest in "${dests[@]}"; do
    dest=$(echo "$dest" | xargs)  # trim
    [ -z "$dest" ] && continue
    local remote_path="${dest}:${BACKUP_REMOTE_ROOT}/${PROJECT_NAME}/${year_month}/"
    log "Uploading -> ${remote_path}"
    if rclone copyto "$dump_path" "${remote_path}${dump_file}" --retries 2 --low-level-retries 3 2>>"$LOG_FILE"; then
      log "  OK ($dest) Subida exitosa"
      success=$((success + 1))
    else
      log "  FAIL ($dest)"
    fi
  done

  if [ "$success" -eq 0 ] && [ "$total" -gt 0 ]; then
    send_alert "upload_failed" "Ningun destino acepto el backup" \
      "El ciclo ${timestamp} fallo en TODOS los destinos remotos (${BACKUP_DESTINATIONS}). El dump local en ${dump_path} esta intacto."
    return 1
  fi
  if [ "$success" -lt "$total" ]; then
    send_alert "upload_partial" "Subida parcial de backup" \
      "El ciclo ${timestamp} solo subio a ${success}/${total} destinos. Revisar logs."
  else
    clear_alert "upload_failed"
    clear_alert "upload_partial"
  fi

  # 4. Local retention
  find "$BACKUPS_DIR" -name "${PROJECT_SLUG}_backup_*.sql.gz" -type f -mtime "+${BACKUP_RETENTION_DAYS}" -delete 2>>"$LOG_FILE" || true

  # 5. Remote retention (filtered by our slug prefix to coexist with other systems)
  for dest in "${dests[@]}"; do
    dest=$(echo "$dest" | xargs); [ -z "$dest" ] && continue
    rclone delete "${dest}:${BACKUP_REMOTE_ROOT}/${PROJECT_NAME}/" \
      --include "${PROJECT_SLUG}_backup_*.sql.gz" \
      --min-age "${BACKUP_RETENTION_DAYS}d" \
      --rmdirs 2>>"$LOG_FILE" || true
  done

  log "Backup completado: ${dump_file}"
  return 0
}

# Allow direct invocation (single cycle) vs sourced by daemon
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_cycle
fi
