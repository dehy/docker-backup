#!/bin/bash

set -eu

source $(dirname $0)/common.sh

echo _NOTE: common

check_vitals

echo _NOTE: check_vitals

install_docker

echo _NOTE: install_docker

THIS_CONTAINER_ID="$(cat /proc/self/cgroup | grep 'docker/' | sed 's/^.*\///' | tail -n1)"
THIS_DOCKER_IMAGE="$(docker inspect ${THIS_CONTAINER_ID} | $BIN_JQ .[0].Config.Image)"
# TODO find the image tag

destinations=$(cat ${CONFIG_FILE} | $BIN_SHYAML keys destinations)

# TODO Global pre-hook
# for destination in $destinations
# do
#     destination_service=$(get_destination_parameter $destination service '')
#     if [ -n "${destination_service}" ]; then
#         echo "(d) Found service ${destination_service}"
#         service_file="/docker-backup-app/services/${destination_service}.sh"
#         if [ -r "${service_file}" ]; then
#             source ${service_file}
#             echo "(d) Configuring service ${destination_service}"
#             service.configure "${destination_service}"
#             echo "(d) Executing ${destination_service} pre-hook instructions"
#             service.global_pre_backup_hook "${destination_service}"
#         else
#             echo "(e) Service configuration file ${service_file} is not readable!"
#         fi
#     fi

#     unset -f service.configure
#     unset -f service.global_pre_backup_hook
#     unset -f service.pre_backup_hook
#     unset -f service.post_backup_success_hook
#     unset -f service.post_backup_failure_hook
#     unset -f service.global_post_backup_hook
# done

sources=$(cat ${CONFIG_FILE} | $BIN_SHYAML keys sources)
if [ -n "${sources}" ]
then
    echo "* Sources found"

    for source in $sources
    do
        echo "* Working on source ${source}"

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

        config_file_hostpath=$(docker inspect ${THIS_CONTAINER_ID} | $BIN_JQ .[0].HostConfig.Binds | grep -E ":${CONFIG_FILE}:" | cut -d":" -f 1 | cut -d'"' -f2)
        if [ -n "${config_file_hostpath}" ]; then
            config_file_volume_opts="-v ${config_file_hostpath}:${CONFIG_FILE}:ro"
        fi
        if [ -z "${config_file_hostpath}" ]; then
            # find if mounted from other container
            mount_points="$(docker inspect ${THIS_CONTAINER_ID} | $BIN_JQ .[0].Mounts)"
            mount_points_count=$(echo "${mount_points}" | $BIN_JQ '. | length')
            i="0"
            while [ $i -lt $mount_points_count ];
            do
                tmp_destination=$(echo "${mount_points}" | $BIN_JQ ".[$i].Destination")
                if [ "$tmp_destination" == "$(dirname ${CONFIG_FILE})" ]; then
                    config_file_hostpath=$(echo "${mount_points}" | $BIN_JQ ".[$i].Source");
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

        echo "(i) Launching Worker for source $source"
        eval docker run --rm --volumes-from ${source_container_id} \
             --name docker-backup-worker-${source_container_name} \
             ${environment_opts} \
             ${network_opts} \
             ${config_file_volume_opts} \
             -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}:ro \
             $THIS_DOCKER_IMAGE worker-config $source
    done

fi # if cat ${CONFIG_FILE} | $BIN_SHYAML keys sources

echo _NOTE: INSTANCE
docker ps -q


for cid in $(docker ps -q)
do
    source_container_id=$cid    # hex

    if [ -z "${source_container_id}" ]; then
        echo "!! No container found with this name! Aborting."
        exit 1
    fi
    if [ $(echo ${source_container_id} | wc -l) -gt 1 ]; then
        echo "!! More than 1 container with this name! Aborting."
        exit 2
    fi
    source_container_name=$(docker_get_container_name_from_id ${source_container_id})

    echo _NOTE: source_container_name=$source_container_name

    destination=$(docker_get_db_destination_from_id $source_container_name)

    echo _NOTE: destination=$destination

    if [ ! -z "$destination" ]
    then
        echo _NOTE: passed

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

        config_file_hostpath=$(docker inspect ${THIS_CONTAINER_ID} | $BIN_JQ .[0].HostConfig.Binds | grep -E ":${CONFIG_FILE}:" | cut -d":" -f 1 | cut -d'"' -f2)
        if [ -n "${config_file_hostpath}" ]; then
            config_file_volume_opts="-v ${config_file_hostpath}:${CONFIG_FILE}:ro"
        fi
        if [ -z "${config_file_hostpath}" ]; then
            # find if mounted from other container
            mount_points="$(docker inspect ${THIS_CONTAINER_ID} | $BIN_JQ .[0].Mounts)"
            mount_points_count=$(echo "${mount_points}" | $BIN_JQ '. | length')
            i="0"
            while [ $i -lt $mount_points_count ];
            do
                tmp_destination=$(echo "${mount_points}" | $BIN_JQ ".[$i].Destination")
                if [ "$tmp_destination" == "$(dirname ${CONFIG_FILE})" ]; then
                    config_file_hostpath=$(echo "${mount_points}" | $BIN_JQ ".[$i].Source");
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

        echo "Launching Worker for source $source_container_name"
        eval docker run --rm --volumes-from ${source_container_id} \
             --name docker-backup-worker-${source_container_name} \
             ${environment_opts} \
             ${network_opts} \
             ${config_file_volume_opts} \
             -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}:ro \
             $THIS_DOCKER_IMAGE worker-env $source_container_name
    else
        echo _NOTE: failed
        echo No destination were present for $source_container_name
    fi
done

exit 0
