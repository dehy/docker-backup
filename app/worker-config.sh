#!/bin/bash

set -eux

source $(dirname $0)/common.sh

install_docker

source=$1
restore=${2:-0}

if [ "$restore" == "restore" -a "$(dir_is_mounted_from_host /docker-restore)" != "0" ]
then
    echo "!!! In restore mode but the /docker-restore dir is not mounted from host" >&2
    exit 1
fi

type=$(get_source_parameter $source type)
source_container_id=$(get_container_id_from_config source $source)
source_container_name=$(docker_get_container_name_from_id $source_container_id)
destination_directory_name=$(get_source_parameter $source name "${source_container_name}")

declare -a volumes_to_backup

if [ "$type" == "mysqldump" ]; then
    username=$(get_source_parameter $source username "")
    if [ -z "$username" ]; then
        username=$(get_config_env_var sources $source username)
    fi
    password=$(get_source_parameter $source password "")
    if [ -z "$password" ]; then
        password=$(get_config_env_var sources $source password)
    fi
    databases=$(get_source_parameter $source databases)

    if [ "$databases" == "*" ]; then
        databases_opt="--all-databases"
    else
        databases_opt="--databases $(echo $databases | tr '\0' ' ')"
    fi

    tmp_dir="/tmp/mysqldump_${destination_directory_name}"
    mkdir -p "${tmp_dir}"
    tmp_file="${tmp_dir}/mysqldump_${destination_directory_name}_$(date +"%Y%m%d%H%M").sql"
    # TODO better security -> write ~/.my.cnf with [mysqldump]\nuser=user\npassword=secret and delete it afterwards
    eval docker exec -i ${source_container_id} mysqldump -u${username} -p${password} ${databases_opt} > ${tmp_file}

    volumes_to_backup[1]="${tmp_dir}"
fi

if [ "$type" == "fs" ]; then
    volumes=$(get_source_parameter $source volumes)
    i=1
    for volume in "${volumes[@]}"
    do
        volumes_to_backup[$i]="$volume"
        i=$(($i+1))
    done
fi

destination=$(get_source_parameter $source destination)
BACKUP_METHOD=$(get_destination_parameter $destination type)
BACKUP_SERVICE=""
if [ -z "${BACKUP_METHOD}" ]; then
    BACKUP_SERVICE=$(get_destination_parameter $destination service)
fi
BACKUP_METHOD_PARAMS=""
BACKUP_KEEP_N_FULL=$(get_parameter backup_keep_n_full)

par2_prefix=""
par2_redundancy_opt=""
PAR2_ENABLED=$(get_parameter par2.enabled false)
if [ "${PAR2_ENABLED}" == "True" ]
then
    par2_prefix="par2+"
    par2_redundancy_opt="--par2-redundancy $(get_parameter par2.redundancy 10)"
fi

BACKUP_METHOD_PARAMS="${BACKUP_METHOD_PARAMS} ${par2_redundancy_opt}"

if [ "${BACKUP_METHOD}" == "ftp" ]
then
    server=$(get_destination_parameter $destination server "")
    if [ -z "${server}" ]; then
        server_id=$(get_container_id_from_config destination $destination)
        server=$(docker_get_container_name_from_id $server_id)
    fi
    port=$(get_destination_parameter $destination port 21)
    username=$(get_destination_parameter $destination username)
    path=$(get_destination_parameter $destination path /)
    BACKUP_URL="${par2_prefix}ftp://${username}@${server}:${port}/${path}/${destination_directory_name}"
    export FTP_PASSWORD=$(get_destination_parameter $destination password "")
fi

if [ "${BACKUP_METHOD}" == "s3" ]
then
    export AWS_ACCESS_KEY_ID=$(get_destination_parameter $destination access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(get_destination_parameter $destination secret_access_key)
    AWS_REGION=$(get_destination_parameter $destination region)
    AWS_BUCKET_NAME=$(get_destination_parameter $destination bucket_name)
    BACKUP_URL="${par2_prefix}s3://s3.${AWS_REGION}.amazonaws.com/${AWS_BUCKET_NAME}/${destination_directory_name}"

    BACKUP_METHOD_PARAMS="${BACKUP_METHOD_PARAMS} --s3-european-buckets --s3-use-new-style"
    if [ "$(get_destination_parameter $destination use_ia False)" == "True" ];
    then
        BACKUP_METHOD_PARAMS="${BACKUP_METHOD_PARAMS} --s3-use-ia"
    fi
fi

if [ "${BACKUP_METHOD}" == "sftp" ]
then
    server=$(get_destination_parameter $destination server "")
    if [ -z "${server}" ]; then
        server_id=$(get_container_id_from_config destination $destination)
        server=$(docker_get_container_name_from_id $server_id)
    fi
    port=$(get_destination_parameter $destination port 21)
    username=$(get_destination_parameter $destination username)
    password=$(get_destination_parameter $destination password)
    path=$(get_destination_parameter $destination path /)
    BACKUP_URL="${par2_prefix}sftp://${username}@${server}:${port}/${path}/${destination_directory_name}"
    export FTP_PASSWORD=$(get_destination_parameter $destination password "")
    mkdir -p ~/.ssh
    ssh-keyscan -p ${port} ${server} >> ~/.ssh/known_hosts
fi

if [ "${BACKUP_SERVICE}" == "c14" ]
then
    source /docker-backup-app/services/c14.sh

    c14_safe_name=$(get_destination_parameter $destination safe_name)
    c14_parity=$(get_destination_parameter $destination parity intensive)
    c14_crypto=$(get_destination_parameter $destination crypto aes-256-cbc)
    c14_platforms=$(get_destination_parameter $destination platform 1)

    c14_archive_name="${source_container_name} - $(date +"%d-%m-%Y %H:%M:%S")"
    c14_archive_description="Docker Backup of ${source_container_name} volumes at $(date +"%d-%m-%Y %H:%M:%S")"

    service.configure "${destination}"

    archive_name="Docker Backup TEST" # $(date +"%Y%m%d%H%M%S")"
    archive_description="Automatic Docker Backup of ..."
    service.pre_backup_hook "$c14_safe_name" "$c14_archive_name" "$c14_archive_description" "$c14_parity" "$c14_crypto" "[\"$c14_platforms\"]"

    export FTP_PASSWORD="${c14_password}"
    BACKUP_URL="${par2_prefix}sftp://${c14_login}@${c14_server}:${c14_port}//buffer/${destination_directory_name}"

    mkdir -p ~/.ssh
    ssh-keyscan -p ${c14_port} ${c14_server} >> ~/.ssh/known_hosts
fi

for volume_to_backup in "${volumes_to_backup[@]}"
do
    if [ "$restore" == "restore" ];
    then
        NOW=$(date +"%Y-%m-%d-%H%M%S")
        restore_destination="/docker-restore/restore-${NOW}"
        duplicity --no-encryption "${BACKUP_URL}" "${restore_destination}/${destination_directory_name}"
        exit 0
    else
        duplicity --full-if-older-than "$(get_parameter backup_full_if_older_than)" \
            --no-encryption --allow-source-mismatch \
            ${BACKUP_METHOD_PARAMS} \
            "${volume_to_backup}" "${BACKUP_URL}"
    fi
done

duplicity remove-all-but-n-full --force --no-encryption "${BACKUP_KEEP_N_FULL}" "${BACKUP_URL}"

if [ "$(type -t service.global_post_backup_hook)" == "function" ]; then
    service.post_backup_success_hook "success"
fi

exit 0
