# inemec_site — Sitio corporativo inemec.com (WordPress autogestionado)

Despliegue Docker del sitio corporativo de Inemec, recuperado tras un ataque y migrado
desde HostGator a infraestructura propia (servidor Inemec.150). Piloto accesible en
`https://site.inemec.com` vía Cloudflare Tunnel.

## Arquitectura

Monolito WordPress detrás de Cloudflare Tunnel — sin puertos expuestos al exterior.

```
Internet -> Cloudflare Tunnel -> cloudflared -> wordpress:80 (Apache + PHP 8.2)
                                                      |
                                                 database (MariaDB 10.11)
                                                      |
                                                 backup (mysqldump + rclone -> SharePoint)
```

| Servicio | Imagen | Notas |
|----------|--------|-------|
| `database` | `mariadb:10.11` | DB `inemecco_wp74`, puerto `127.0.0.1:3306` (solo loopback) |
| `wordpress` | `wordpress:7.0-php8.2-apache` | Puerto `127.0.0.1:8080` (loopback, para diagnostico) |
| `backup` | Alpine + mariadb-client + rclone | Dump cada 10 min a SharePoint, alertas SMTP |
| `cloudflared` | `cloudflare/cloudflared:latest` | Perfil `tunnel`; requiere `TUNNEL_TOKEN` |

Difiere del patron estandar del entorno (FastAPI/Node + PostgreSQL): es WordPress + MariaDB,
por lo que tiene su propio script de backup (`backup/scripts/backup_mysql.sh`) en vez de los
scripts canonicos basados en `pg_dump`.

## Estructura

```
inemec_site/
├── docker-compose.tunnel.yml   # Definicion de los 4 servicios
├── deploy-tunnel.sh            # Script de gestion (start/stop/status/backup-*/go-live/...)
├── .env.tunnel.example         # Plantilla de variables (copiar a .env.tunnel)
├── backup/
│   ├── Dockerfile
│   └── scripts/                # backup_daemon.sh + backup_mysql.sh
├── db-init/                    # Dump SQL de inicializacion (NO versionado — datos reales)
├── backups/mysql/              # Backups locales (NO versionado)
├── wordpress/                  # WP core + wp-content (NO versionado — runtime)
└── originals/                  # Backups crudos de origen (NO versionado — pesado)
```

## Puesta en marcha

```bash
cp .env.tunnel.example .env.tunnel    # rellenar TUNNEL_TOKEN, passwords, SMTP_PASS
# colocar el dump inicial en db-init/01_inemecco_wp74.sql
# colocar el rclone.conf compartido en backup/rclone_config/rclone.conf

./deploy-tunnel.sh build              # construye la imagen de backup
./deploy-tunnel.sh start              # levanta database + wordpress + backup
./deploy-tunnel.sh tunnel-up          # levanta cloudflared (requiere TUNNEL_TOKEN valido)
./deploy-tunnel.sh status             # estado + ultimos backups
```

Ver `./deploy-tunnel.sh help` para todos los comandos.

## Notas operativas

- **Correo (PQRS / Contacto)**: el contenedor no trae MTA; el envio se hace por SMTP de
  Office365 via el plugin WP Mail SMTP (configurado en `wp_options`). El remitente se fuerza
  a `ti.automatizacion@inemec.com` porque Office365 exige que coincida con la cuenta autenticada.
- **Miniaturas**: tras restaurar uploads conviene `wp media regenerate` para regenerar las
  variantes redimensionadas que WordPress genera bajo demanda.
- **Migracion a inemec.com**: el piloto corre en `site.inemec.com`. Para el cambio definitivo,
  reapuntar el hostname del tunel a `inemec.com` y actualizar `WP_HOME`/`WP_SITEURL`
  (el comando `go-live` automatiza el cambio de URLs).

## Seguridad

- `wp-config.php` tiene `DISALLOW_FILE_EDIT` y `DISALLOW_FILE_MODS` activos.
- Ningun secreto se versiona: `.env.tunnel`, `db-init/*.sql`, `rclone.conf` y `.claude/`
  estan en `.gitignore`.
