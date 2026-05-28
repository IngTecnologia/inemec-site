#!/usr/bin/env bash
# Script maestro de gestion para inemec_site (piloto WordPress).
#
# Uso: ./deploy-tunnel.sh <comando>
#
# Comandos:
#   start              - Levanta DB + WordPress + backup. Cloudflared queda dormido
#                        (perfil 'tunnel') hasta que TUNNEL_TOKEN sea real.
#   stop               - Detiene todos los servicios sin borrar volumenes.
#   restart            - stop + start.
#   logs [servicio]    - Sigue logs (sin arg = todos).
#   status             - Estado contenedores + URLs + ultimos backups.
#   build              - Rebuild de imagenes locales (backup container).
#
#   inject-uploads     - Descomprime originals/*-uploads.zip dentro de
#                        wordpress/wp-content/uploads/ (correr cuando WP ya este Up).
#   inject-zip <ruta>  - Descomprime un ZIP de cPanel (themes/plugins) dentro de
#                        wordpress/wp-content/ con escaneo basico de malware.
#
#   tunnel-up          - Levanta tambien cloudflared (asume TUNNEL_TOKEN valido).
#   tunnel-down        - Apaga cloudflared (sin afectar el resto).
#   go-live            - Cambia WP_HOME/WP_SITEURL de localhost:8080 a https://inemec.com,
#                        recrea wordpress y levanta el tunel. Confirmacion explicita.
#
#   backup-manual      - Disparar un backup ahora mismo (sin esperar al daemon).
#   backup-logs        - Ultimas lineas del daemon de backup.
#   backup-list        - Lista backups remotos en SharePoint.
#   backup-local       - Lista backups locales (./backups/mysql/).
#
#   restore <archivo>  - Restaurar la DB desde un .sql.gz local (peligroso, confirma).
#   db-shell           - Abrir mysql shell dentro del contenedor database.
#   wp-shell           - Abrir bash dentro del contenedor wordpress.

set -euo pipefail

cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.tunnel.yml --env-file .env.tunnel"
ENV_FILE=".env.tunnel"

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
blue()   { printf "\033[34m%s\033[0m\n" "$*"; }

require_env() {
  if [ ! -f "$ENV_FILE" ]; then
    red "Falta $ENV_FILE. Aborto."
    exit 1
  fi
}

check_tunnel_token() {
  local t
  t=$(grep -E '^TUNNEL_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
  if [ -z "$t" ] || [[ "$t" == PENDIENTE* ]] || [[ "$t" == CHANGE_ME* ]]; then
    return 1
  fi
  return 0
}

cmd_start() {
  require_env
  blue "Levantando database + wordpress..."
  # NOTA: el servicio 'backup' esta deshabilitado para este piloto (no se requiere
  # protocolo de backup). Para reactivarlo: agregar 'backup' a la linea de abajo
  # y reconstruir con: $0 build && $COMPOSE up -d backup
  $COMPOSE up -d database wordpress
  echo
  green "Servicios arrancados. Probar en: $(grep ^WP_HOME "$ENV_FILE" | cut -d= -f2-)"
  echo "  (puerto 8080 expuesto solo en loopback del host por seguridad)"
  if ! check_tunnel_token; then
    yellow "TUNNEL_TOKEN aun no configurado -- cloudflared NO levantado."
    yellow "Cuando tengas el token, editar .env.tunnel y ejecutar: $0 tunnel-up"
  fi
}

cmd_stop() {
  require_env
  blue "Deteniendo servicios..."
  $COMPOSE down
}

cmd_restart() {
  cmd_stop || true
  cmd_start
}

cmd_logs() {
  require_env
  local svc="${1:-}"
  if [ -n "$svc" ]; then
    $COMPOSE logs -f --tail 100 "$svc"
  else
    $COMPOSE logs -f --tail 50
  fi
}

cmd_status() {
  require_env
  blue "=== Servicios ==="
  $COMPOSE ps
  echo
  blue "=== URLs ==="
  echo "  Local:  $(grep ^WP_HOME "$ENV_FILE" | cut -d= -f2-)"
  if check_tunnel_token; then
    echo "  Tunnel: configurado"
  else
    yellow "  Tunnel: NO configurado (TUNNEL_TOKEN pendiente)"
  fi
  echo
  blue "=== Ultimos backups locales ==="
  ls -lht ./backups/mysql/ 2>/dev/null | head -6 || yellow "  (sin backups locales)"
  echo
  blue "=== Backup daemon (ultimas lineas) ==="
  docker logs inemecsite-backup --tail 8 2>&1 | sed 's/^/  /' || true
}

cmd_build() {
  require_env
  $COMPOSE build backup
}

cmd_inject_uploads() {
  require_env
  local zip
  zip=$(ls -1 ./originals/*uploads*.zip 2>/dev/null | head -1)
  if [ -z "$zip" ]; then
    red "No encontre ningun ZIP de uploads en ./originals/"
    exit 1
  fi
  blue "Descomprimiendo $zip..."
  if [ ! -d "./wordpress/wp-content" ]; then
    red "WordPress aun no inicializado (./wordpress/wp-content no existe)."
    red "Arrancar primero con: $0 start (esperar ~30s a que el entrypoint poble wordpress/)"
    exit 1
  fi
  # Use a temporary container with unzip to preserve permissions consistent with the wordpress container
  docker run --rm -v "$PWD/originals:/in:ro" -v "$PWD/wordpress:/out" alpine:3.18 \
    sh -c 'apk add --no-cache unzip > /dev/null && \
           cd /tmp && unzip -q "/in/$(basename '"$zip"')" && \
           mkdir -p /out/wp-content/uploads && \
           cp -rT uploads/ /out/wp-content/uploads/ && \
           echo "OK"'
  # Fix ownership to match www-data inside the wordpress image (uid 33)
  docker exec inemecsite_wordpress chown -R www-data:www-data /var/www/html/wp-content/uploads
  green "Uploads inyectados. Verifica navegando a /wp-admin/upload.php"
}

cmd_inject_zip() {
  require_env
  local zip="${1:-}"
  if [ -z "$zip" ] || [ ! -f "$zip" ]; then
    red "Uso: $0 inject-zip <ruta-al-zip>"
    red "Ejemplo: $0 inject-zip ./originals/plugins.zip"
    exit 1
  fi
  if [ ! -d "./wordpress/wp-content" ]; then
    red "WordPress aun no inicializado. Arrancar primero con: $0 start"
    exit 1
  fi
  blue "Descomprimiendo $zip a temporal y escaneando..."
  local tmpdir
  tmpdir=$(mktemp -d)
  docker run --rm -v "$tmpdir:/out" -v "$(realpath "$zip"):/in.zip:ro" alpine:3.18 \
    sh -c 'apk add --no-cache unzip > /dev/null && unzip -q /in.zip -d /out && echo OK'
  echo
  yellow "=== Escaneo malware basico (eval, base64_decode, webshells) ==="
  grep -rlE "eval[[:space:]]*\([[:space:]]*base64_decode|eval[[:space:]]*\([[:space:]]*gzinflate|str_rot13[[:space:]]*\([[:space:]]*['\"]" "$tmpdir" 2>/dev/null | sed 's|^'"$tmpdir"'|  HIT: |' || echo "  (sin coincidencias obvias)"
  echo
  yellow "=== Plugins con nombres sospechosos (los 2 ya conocidos) ==="
  find "$tmpdir" -maxdepth 4 -type d \( -iname "*digestorium*" -o -iname "*organism-alimentarium*" -o -iname "*bureaucracy*" \) | sed 's|^|  HIT: |' || echo "  (limpio)"
  echo
  echo "Contenido descomprimido en: $tmpdir"
  echo "Revisa los HIT arriba. Luego corre manualmente:"
  echo "  cp -r $tmpdir/* ./wordpress/wp-content/<destino>/"
  echo "  docker exec inemecsite_wordpress chown -R www-data:www-data /var/www/html/wp-content"
  echo "Cuando termines: rm -rf $tmpdir"
}

cmd_tunnel_up() {
  require_env
  if ! check_tunnel_token; then
    red "TUNNEL_TOKEN no configurado en .env.tunnel. Configurar primero."
    exit 1
  fi
  $COMPOSE --profile tunnel up -d cloudflared
  green "Cloudflared levantado."
}

cmd_tunnel_down() {
  require_env
  $COMPOSE stop cloudflared || true
}

cmd_go_live() {
  require_env
  if ! check_tunnel_token; then
    red "TUNNEL_TOKEN no configurado. Aborto."
    exit 1
  fi
  yellow "Esta accion cambia WP_HOME y WP_SITEURL a https://inemec.com"
  yellow "y levanta el tunel Cloudflare."
  read -r -p "Continuar? [yes/N] " ans
  if [ "$ans" != "yes" ]; then echo "Cancelado."; exit 0; fi

  sed -i "s|^WP_HOME=.*|WP_HOME=https://inemec.com|" .env.tunnel
  sed -i "s|^WP_SITEURL=.*|WP_SITEURL=https://inemec.com|" .env.tunnel

  blue "Recreando wordpress con nuevas URLs..."
  $COMPOSE up -d --force-recreate --no-deps wordpress
  cmd_tunnel_up
  green "Listo. Verifica https://inemec.com en unos segundos."
}

cmd_backup_manual() {
  require_env
  blue "Ejecutando ciclo de backup ahora..."
  docker exec inemecsite-backup /app/scripts/backup_mysql.sh
}

cmd_backup_logs() {
  docker logs inemecsite-backup --tail 60
}

cmd_backup_list() {
  blue "=== Backups remotos (SharePoint) ==="
  docker exec inemecsite-backup rclone ls \
    "sharepoint_jesus_corp:Inemec.150/backups/InemecSite/" 2>/dev/null \
    | sort -k1,1 | tail -20 \
    || red "rclone fallo (token expirado?)"
}

cmd_backup_local() {
  blue "=== Backups locales ==="
  ls -lht ./backups/mysql/ 2>/dev/null | head -20 || yellow "  (sin backups locales)"
}

cmd_restore() {
  require_env
  local file="${1:-}"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    red "Uso: $0 restore <archivo.sql.gz>"
    red "Ejemplo: $0 restore backups/mysql/inemecsite_backup_20260528_120000.sql.gz"
    exit 1
  fi
  yellow "ATENCION: esto SOBRESCRIBE la DB ${WP_DB_NAME:-inemecco_wp74}"
  yellow "Archivo: $file"
  read -r -p "Continuar? [yes/N] " ans
  if [ "$ans" != "yes" ]; then echo "Cancelado."; exit 0; fi
  source <(grep -E '^WP_DB_(NAME|USER|PASSWORD|ROOT_PASSWORD)=' "$ENV_FILE")
  gunzip -c "$file" | docker exec -i inemecsite_database \
    sh -c "MYSQL_PWD=\"$WP_DB_ROOT_PASSWORD\" mariadb -uroot"
  green "Restore completado."
}

cmd_db_shell() {
  require_env
  source <(grep -E '^WP_DB_(NAME|USER|PASSWORD)=' "$ENV_FILE")
  docker exec -it inemecsite_database \
    sh -c "MYSQL_PWD=\"$WP_DB_PASSWORD\" mariadb -u$WP_DB_USER $WP_DB_NAME"
}

cmd_wp_shell() {
  docker exec -it inemecsite_wordpress bash
}

cmd_help() {
  sed -n '2,40p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
  start)           shift; cmd_start "$@" ;;
  stop)            shift; cmd_stop "$@" ;;
  restart)         shift; cmd_restart "$@" ;;
  logs)            shift; cmd_logs "$@" ;;
  status)          shift; cmd_status "$@" ;;
  build)           shift; cmd_build "$@" ;;
  inject-uploads)  shift; cmd_inject_uploads "$@" ;;
  inject-zip)      shift; cmd_inject_zip "$@" ;;
  tunnel-up)       shift; cmd_tunnel_up "$@" ;;
  tunnel-down)     shift; cmd_tunnel_down "$@" ;;
  go-live)         shift; cmd_go_live "$@" ;;
  backup-manual)   shift; cmd_backup_manual "$@" ;;
  backup-logs)     shift; cmd_backup_logs "$@" ;;
  backup-list)     shift; cmd_backup_list "$@" ;;
  backup-local)    shift; cmd_backup_local "$@" ;;
  restore)         shift; cmd_restore "$@" ;;
  db-shell)        shift; cmd_db_shell "$@" ;;
  wp-shell)        shift; cmd_wp_shell "$@" ;;
  help|-h|--help)  cmd_help ;;
  *) red "Comando desconocido: $1"; cmd_help; exit 1 ;;
esac
