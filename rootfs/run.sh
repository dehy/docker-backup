#!/bin/bash

if [ "$1" == "bash" ]
then
    exec /bin/bash
    exit 0
fi

set -x

# TODO : Tester la présence de /var/run/docker.sock
# TODO : Tester la présence de la variable d'environnement $BACKUP_URL
# TODO : Si format = S3, checker les variables BACKUP_S3_ACCESS_KEY_ID et BACKUP_S3_SECRET_ACCESS_KEY

DOCKER_SOCKET="unix:///var/run/docker.sock"
DOCKER_GET="curl-unix-socket -X GET -H 'Accept: application/json' ${DOCKER_SOCKET}"
DOCKER_POST="curl-unix-socket -X POST -H 'Accept: application/json|Content-type: application/json' ${DOCKER_SOCKET}"

if [ "$1" == "worker" ]; then

    # volume = $2
    # container = $3

    if [ "${BACKUP_METHOD}" == "ftp" ]
    then
        duplicity  --full-if-older-than 7D --no-encryption --allow-source-mismatch --archive-dir=$3 --name=$3 $2 ${BACKUP_URL}
    fi

    if [ "${BACKUP_METHOD}" == "s3" ]
    then
        duplicity --full-if-older-than 7D --no-encryption --allow-source-mismatch --s3-european-buckets --s3-use-new-style --archive-dir=$3 --name=$3 $2 ${BACKUP_URL}
    fi

    exit 0
fi

docker_engine_version=$(eval $DOCKER_GET:/version | underscore select ".Version" --outfmt text)
docker_engine_package_version=$(apt-cache showpkg docker-engine | grep ${docker_engine_version} | tail -n 1 | awk '{ print $1 }')
apt-get install docker-engine=${docker_engine_package_version}

for volume_to_backup in $@
do
    backup_data=(${volume_to_backup//:/ })
    container_name=${backup_data[0]}
    container_volume=${backup_data[1]}

    # TODO : Tester si le volume est bien exporté depuis le container

    if [ "$BACKUP_METHOD" == "ftp" ]
    then
        env_opts="-e \"FTP_PASSWORD=${FTP_PASSWORD}\""
    fi

    if [ "$BACKUP_METHOD" == "s3" ]
    then
        env_opts="-e \"AWS_ACCESS_KEY_ID=${BACKUP_S3_ACCESS_KEY_ID}\" -e \"AWS_SECRET_ACCESS_KEY=${BACKUP_S3_SECRET_ACCESS_KEY}\""
    fi

    eval docker run --rm --volumes-from ${container_name} \
        -e "BACKUP_METHOD=${BACKUP_METHOD}" \
        -e "BACKUP_URL=${BACKUP_URL}" \
        ${env_opts} \
        akerbis/data-container-backup worker ${container_volume} ${container_name}

    # container_id=`curl-unix-socket unix:///var/run/docker.sock:/containers/json | underscore select ":has(:root > .Names > :contains(\"${container_name}\")) .Id:val" --outfmt text`
    # echo $container_id
    # found_volume=`curl-unix-socket unix:///var/run/docker.sock:/containers/${container_id}/json | underscore select ":root > .Mounts .Destination:val(\"${container_volume}\")" --outfmt text`

done
