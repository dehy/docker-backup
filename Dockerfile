FROM ubuntu:16.04
MAINTAINER Arnaud de Mouhy <arnaud.demouhy@akerbis.com>

COPY docker/image_setup /image_setup
RUN bash /image_setup/build_image.sh && rm -rf /image_setup
COPY app /docker-backup-app

ENTRYPOINT [ "bash", "/docker-backup-entrypoint.sh" ]
