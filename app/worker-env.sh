#!/bin/bash

set -eu

source $(dirname $0)/common.sh

install_docker

# source=$1
source_container_id=$1
restore=${2:-0}

if [ "$restore" == "restore" -a "$(dir_is_mounted_from_host /docker-restore)" != "0" ]
then
    echo "!!! In restore mode but the /docker-restore dir is not mounted from host" >&2
    exit 1
fi

# source_container_id=$(get_container_id_from_config source $source)
source_container_name=$(docker_get_container_name_from_id $source_container_id)
destination_directory_name=$(docker_get_db_destpath_from_id $source_container_id "${source_container_name}")

declare -a volumes_to_backup

volumes_path=$(docker_get_db_volumes_from_id $source_container_id)
echo _NOTE: volumes_path=$volumes_path
# IFS=':' volumes=($volumes_path)
volumes=( $(echo $volumes_path | sed 's/:/ /g' ) )
echo _NOTE: volumes=$volumes

i=1
for volume in "${volumes[@]}"
do
    volumes_to_backup[$i]="$volume"
    i=$(($i+1))
done


destination=$(docker_get_db_destination_from_id $source_container_name)

if [ ! -z "$destination" ]
then

    echo _NOTE: destination=$destination


    BACKUP_METHOD=$(get_destination_parameter $destination type)
    echo "(d) Backup Method: ${BACKUP_METHOD}"
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

    echo "(d) Backup URL: ${BACKUP_URL}"

    for volume_to_backup in "${volumes_to_backup[@]}"
    do
        if [ -d "${volume_to_backup}" ]
        then
            if [ "$restore" == "restore" ];
            then
                echo "(i) I will restore volume ${volume_to_backup} of container ${source_container_name} via ${BACKUP_METHOD} from ${BACKUP_URL}..."

                docker_run_cmd_in_container $source_container_id $(docker_get_db_restore_precmd_from_id $source_container_id)

                NOW=$(date +"%Y-%m-%d-%H%M%S")
                restore_destination="/docker-restore/restore-${NOW}"
                duplicity --no-encryption "${BACKUP_URL}" "${restore_destination}/${destination_directory_name}"

                docker_run_cmd_in_container $source_container_id $(docker_get_db_restore_postcmd_from_id $source_container_id)

                exit 0
            else
                echo "(i) I will backup volume ${volume_to_backup} of container ${source_container_name} via ${BACKUP_METHOD} to ${BACKUP_URL}..."

                docker_run_cmd_in_container $source_container_id $(docker_get_db_backup_precmd_from_id $source_container_id)

                duplicity --full-if-older-than "$(get_parameter backup_full_if_older_than)" \
                          --no-encryption --allow-source-mismatch \
                          ${BACKUP_METHOD_PARAMS} \
                          "${volume_to_backup}" "${BACKUP_URL}"

                docker_run_cmd_in_container $source_container_id $(docker_get_db_backup_postcmd_from_id $source_container_id)
            fi
        else
            echo No "${volume_to_backup}" such directory exist for ${restore:-backup}.
        fi
    done

    echo "(i) I will purge all old backups with more than ${BACKUP_KEEP_N_FULL} full backups"
    duplicity remove-all-but-n-full --force --no-encryption "${BACKUP_KEEP_N_FULL}" "${BACKUP_URL}"

else
    echo No destination were present for $source_container_name
fi # if [ ! -z "$destination" ]

exit 0
