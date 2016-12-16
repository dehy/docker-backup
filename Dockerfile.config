FROM busybox

COPY ./app/config.yml.dist /etc/docker-backup/docker-backup.yml
VOLUME /etc/docker-backup

CMD tail -f /dev/null
