#!/bin/bash

set -eux

ACTION=${1:-default}

if [ ! -f '/etc/docker-backup/docker-backup.yml' ]; then
    if [ ! -r '/docker-backup-app/config.yml' ]; then
        echo "!!! You need to copy config.yml.dist to config.yml and override parameters"
        exit 1
    fi
    mkdir -p /etc/docker-backup
    cp /docker-backup-app/config.yml /etc/docker-backup/docker-backup.yml
fi

export -p | grep 'CONFIG_' > /docker-backup-environment.sh

if [ "$ACTION" == "bash" ]
then
    exec /bin/bash
    exit 0
fi

if [ "$ACTION" == "debug" ]
then
    tail -f /dev/null
    exit 0
fi

if [ "$ACTION" == "force" ]; then
    /bin/bash /docker-backup-app/run.sh
    exit 0
fi

if [ "$ACTION" == "worker-config" ]; then
    container=$2
    /bin/bash /docker-backup-app/worker-config.sh $container
    exit 0
fi

if [ "$ACTION" == "worker-env" ]; then
    container=$2
    /bin/bash /docker-backup-app/worker-env.sh $container
    exit 0
fi

if [ "$ACTION" == "restore" ]; then
    shift
    while (( "$#" ));
    do
        container=$1
        /bin/bash /docker-backup-app/worker.sh $container restore
        shift
    done
    exit 0
fi

/usr/sbin/cron -f -L 15
