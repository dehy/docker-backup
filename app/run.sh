#!/bin/bash

set -eux

source $(dirname $0)/common.sh

check_vitals

install_docker

THIS_CONTAINER_ID="$(cat /proc/self/cgroup | grep 'docker/' | sed 's/^.*\///' | tail -n1)"
THIS_DOCKER_IMAGE="$(docker inspect ${THIS_CONTAINER_ID} | $BIN_UNDERSCORE extract 0.Config.Image --outfmt text)"
# TODO find the image tag

destinations=$(cat ${CONFIG_FILE} | $BIN_SHYAML keys destinations)
sources=$(cat ${CONFIG_FILE} | $BIN_SHYAML keys sources)
for source in $sources
do
    type=$(get_source_parameter $source type)
    # container, compose or docker-cloud ?
    source_container_id=$(get_container_id_from_config source $source)

    if [ -z "${source_container_id}" ]; then
        echo "!! No container found with this name! Aborting."
        exit 1
    fi
    if [ $(echo ${source_container_id} | wc -l) -gt 1 ]; then
        echo "!! More than 1 container with this name! Aborting."
        exit 2
    fi
    source_container_name=$(docker_get_container_name_from_id ${source_container_id})

    destination=$(get_source_parameter $source destination)
    config_destination_server=$(get_destination_parameter $destination server "")

    # Networking
    network_opts=""
    if [ -z "$config_destination_server" ]; then
        destination_container_id=$(get_container_id_from_config destination $destination)
        if [ -n "${destination_container_id}" -a "$(echo ${destination_container_id} | wc -l)" -eq 1 ]; then
            network_opts="--network=container:${destination_container_id}"
        fi
    fi

    # If the config file is mounted from host, find the host path
    config_file_mounted_hostpath=$(docker inspect $(hostname) | $BIN_UNDERSCORE extract 0.HostConfig.Binds --outfmt text | grep -E ":$(dirname ${CONFIG_FILE})(/$(basename ${CONFIG_FILE}))?:" | cut -d":" -f 1)
    config_file_volume_opts=""
    if [ -n "$config_file_mounted_hostpath" ]; then
        if [ "$(basename ${config_file_mounted_hostpath})" != "$(basename ${CONFIG_FILE})" ]; then
            config_file_hostpath="${config_file_mounted_hostpath}/$(basename ${CONFIG_FILE})"
        else
            config_file_hostpath="${config_file_mounted_hostpath}"
        fi
        config_file_volume_opts="-v ${config_file_hostpath}:${CONFIG_FILE}:ro"
    fi

    ENV_VARIABLES=$(env | grep "^CONFIG_")
    environment_opts=""
    for config_var in ${ENV_VARIABLES}
    do
        environment_opts="${environment_opts} -e ${config_var}"
    done

    echo "Launching Worker for source $source"
    eval docker run --rm --volumes-from ${source_container_id} \
        --name docker-backup-worker-${source_container_name} \
        ${environment_opts} \
        ${network_opts} \
        ${config_file_volume_opts} \
        -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}:ro \
        $THIS_DOCKER_IMAGE worker $source
done

exit 0
