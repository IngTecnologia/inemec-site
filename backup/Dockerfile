FROM alpine:3.18

RUN apk add --no-cache \
    rclone curl bash coreutils tzdata gzip mariadb-client

ENV TZ=America/Bogota
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN mkdir -p /app/scripts /app/logs /app/temp /app/backups

COPY scripts/ /app/scripts/

RUN chmod +x /app/scripts/*.sh && \
    sed -i 's/\r$//' /app/scripts/*.sh

WORKDIR /app

CMD ["/bin/bash", "-c", "exec /app/scripts/backup_daemon.sh"]
