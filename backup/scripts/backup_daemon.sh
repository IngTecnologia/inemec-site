#!/usr/bin/env bash
# Loop infinito que ejecuta un ciclo de backup cada BACKUP_INTERVAL segundos.
# Espejo del backup_daemon.sh canonico de los otros proyectos, pero llama a backup_mysql.sh.

set -uo pipefail

LOG_FILE="/app/logs/backup_daemon.log"
mkdir -p "$(dirname "$LOG_FILE")"

INTERVAL="${BACKUP_INTERVAL:-600}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Daemon starting. Interval: ${INTERVAL}s. Project: ${PROJECT_NAME:-?}/${PROJECT_SLUG:-?}"

# small startup delay to let the DB warm up
sleep 30

while true; do
  log "Triggering backup cycle"
  if /app/scripts/backup_mysql.sh; then
    log "Cycle ended OK"
  else
    log "Cycle ended with errors (continuing)"
  fi
  log "Sleeping ${INTERVAL}s"
  sleep "$INTERVAL"
done
