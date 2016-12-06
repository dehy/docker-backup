#!/bin/bash

set -eux

ACTION=${1:-default}

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

if [ "$ACTION" == "worker" ]; then
    container=$2
    /bin/bash /docker-backup-app/worker.sh $container
    exit 0
fi

/usr/sbin/cron -f -L 15
