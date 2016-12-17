#!/bin/bash

set -eux

source $(dirname $0)/common.sh

check_vitals

install_docker

THIS_CONTAINER_ID="$(cat /proc/self/cgroup | grep 'docker/' | sed 's/^.*\///' | tail -n1)"
THIS_DOCKER_IMAGE="$(docker inspect ${THIS_CONTAINER_ID} | underscore extract 0.Config.Image --outfmt text)"
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

    # If the config file is mounted from host or other container, find the way to get it to workers containers
    config_file_volume_opts=""

    config_file_hostpath=$(docker inspect ${THIS_CONTAINER_ID} | underscore extract 0.HostConfig.Binds --outfmt text | grep -E ":${CONFIG_FILE}:" | cut -d":" -f 1)
    if [ -n "${config_file_hostpath}" ]; then
        config_file_volume_opts="-v ${config_file_hostpath}:${CONFIG_FILE}:ro"
    fi
    if [ -z "${config_file_hostpath}" ]; then
        # find if mounted from other container
        mount_points="$(docker inspect ${THIS_CONTAINER_ID} | underscore extract 0.Mounts)"
        mount_points_count=$(echo "${mount_points}" | underscore process 'data.length')
        i="0"
        while [ $i -lt $mount_points_count ];
        do
            tmp_destination=$(echo "${mount_points}" | underscore extract "$i.Destination" --outfmt text)
            if [ "$tmp_destination" == "$(dirname ${CONFIG_FILE})" ]; then
                config_file_hostpath=$(echo "${mount_points}" | underscore extract "$i.Source" --outfmt text);
                break
            fi
            unset tmp_destination
            i=$[$i+1]
        done
        unset i mount_points mount_points_count tmp_destination

        if [ -n "$config_file_hostpath" ]; then
            config_file_volume_opts="-v ${config_file_hostpath}:$(dirname ${CONFIG_FILE}):ro"
        fi
    fi
    unset config_file_hostpath

    # Give the worker container the variables that override config file
    environment_opts=""
    ENV_VARIABLES=$(env | grep "^CONFIG_")
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
