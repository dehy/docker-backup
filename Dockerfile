FROM ubuntu:16.04
MAINTAINER Arnaud de Mouhy <arnaud.demouhy@akerbis.com>

ARG BUILD_DATE
ARG VCS_REF
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/akerbis/docker-backup" \
      org.label-schema.schema-version="1.0"

COPY docker/image_setup /image_setup
RUN bash /image_setup/build_image.sh && rm -rf /image_setup

ARG INCUBATOR_VER=unknown
RUN INCUBATOR_VER=${INCUBATOR_VER} pwd
COPY app /docker-backup-app

ENTRYPOINT [ "bash", "/docker-backup-entrypoint.sh" ]
