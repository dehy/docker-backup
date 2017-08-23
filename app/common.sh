#!/bin/bash

set -eux

source /docker-backup-environment.sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

BIN_UNDERSCORE=/usr/local/bin/underscore
BIN_SHYAML=/usr/local/bin/shyaml

CONFIG_FILE="/etc/docker-backup/docker-backup.yml"

DOCKER_SOCKET="/var/run/docker.sock"
DOCKER_GET="curl -XGET -H 'Accept: application/json' --unix-socket ${DOCKER_SOCKET} http://localhost"
DOCKER_POST="curl -XPOST -H 'Accept: application/json|Content-type: application/json' --unix-socket ${DOCKER_SOCKET} http://localhost"

function check_vitals {
    # TODO: check if config file is present and readable
    # check if /var/run/docker.sock is present and readable
    # Advanced: check docker-backup.yml validity
    echo ""
}

function install_docker {
    docker_engine_version=$(eval $DOCKER_GET/version | underscore select ".Version" --outfmt text)
    docker_api_version=$(eval $DOCKER_GET/version | underscore select ".ApiVersion" --outfmt text)
    # Remove commercialy supported extension
    docker_engine_version=$(echo ${docker_engine_version} | sed -E 's/~cs[0-9]+$//')

    echo "(i) Docker engine version is ${docker_engine_version}. Installing package..."

    # docker-engine or docker-ce?
    is_docker_ce=$(echo ${docker_engine_version} | sed -n -e '/-ce/p')
    local docker_package_name="docker-ce"
    if [ -z "${is_docker_ce}" ]; then
        docker_package_name="docker-engine"
    fi
    # is from test channel? (release candidates builds)
    is_release_candidate=$(echo ${docker_engine_version} | sed -n -e '/-rc[0-9]+/p')
    if [ -z "${is_release_candidate}" ]; then
        # add test channel to docker repository
        sed -i -e 's/edge/edge test/g' /etc/apt/sources.list.d/docker-ce.list
        apt-get -qq update
    fi

    local docker_package_version=$(echo ${docker_engine_version} | tr '-' '~')
    # local docker_engine_package_version=$(apt-cache madison docker-engine | grep ${package_version} | awk -F "|" '{ print $2 }' | tr -d " ")
    apt-get -qq install -y --no-install-recommends ${docker_package_name}=${docker_package_version}*
}

function docker_get {
    local url_path="${1:-/}"
    eval ${DOCKER_GET}${url_path}
}

function docker_get_current_container_id {
    cat /proc/1/cgroup | grep 'docker/' | tail -1 | sed 's/^.*\///' | cut -c 1-12
}

function docker_get_container_name_from_id {
    local container_id=$1
    docker inspect ${container_id} | underscore extract 0.Name --outfmt text | sed -e 's#^/##'
}

function docker_get_container_id_from_name {
    local container_name=$1
    docker inspect ${container_name} | underscore extract 0.Id --outfmt text
}

function get_container_id_from_config {
    local property=$1
    local key=$2
    local config_container=$(get_${property}_parameter $key container "")
    local config_compose=$(get_${property}_parameter $key compose "")
    local config_dockercloud=$(get_${property}_parameter $key dockercloud "")
    local container_id=""
    if [ -n "${config_container}" ]
    then
        container_id=$(docker inspect ${config_container} | ${BIN_UNDERSCORE} extract 0.Id --outfmt text)
    elif [ -n "${config_compose}" ]
    then
        local config_compose_project=$(get_${property}_parameter $key compose.project "")
        local config_compose_service=$(get_${property}_parameter $key compose.service "")
        local config_compose_container_number=$(get_${property}_parameter $key compose.container_number 1)
        local guessed_container_name=${config_compose_project}_${config_compose_service}_${config_compose_container_number}
        container_id=$(docker_get_container_id_from_name ${guessed_container_name})
    elif [ -n "${config_dockercloud}" ]
    then
        local config_dockercloud_stack=$(get_${property}_parameter $key dockercloud.stack "")
        local config_dockercloud_service=$(get_${property}_parameter $key dockercloud.service "")
        local config_dockercloud_container_number=$(get_${property}_parameter $key dockercloud.container_number 1)
        local guessed_container_partial_name=${config_dockercloud_service}-${config_dockercloud_container_number}.${config_dockercloud_stack}
        local container_name=$(docker ps -a | grep -E "\s+${guessed_container_partial_name}\.[0-9a-f]{8}$" | awk '{ print $1 }')
        container_id=$(docker_get_container_id_from_name ${container_name})
    fi

    echo ${container_id}
}

function docker_get_db_value_id {
    local container_name=$1
    local varname=$2
    local default="${3:-}"
    if docker inspect ${container_name} | underscore extract 0.Config.Env --outfmt text | grep $varname= 2>&1 >/dev/null &&
           docker inspect ${container_name} | underscore extract 0.Config.Env --outfmt text | grep $varname= | cut -d= -f2- | grep . 2>&1 >/dev/null
    then
        echo $(echo $(docker inspect ${container_name} | underscore extract 0.Config.Env --outfmt text | grep $varname= | cut -d= -f2-))
    else
        echo $default
    fi
}

function docker_get_db_volumes_from_id {
    docker_get_db_value_id $1 "DB_VOLUMES" "${2:-}"
}

function docker_get_db_destination_from_id {
    docker_get_db_value_id $1 "DB_DESTINATION" "${2:-}"
}

function docker_get_db_destpath_from_id {
    docker_get_db_value_id $1 "DB_DESTPATH" "${2:-}"
}

function docker_get_db_backup_precmd_from_id {
    docker_get_db_value_id $1 "DB_BACKUP_PRECMD" "${2:-}"
}

function docker_get_db_backup_postcmd_from_id {
    docker_get_db_value_id $1 "DB_BACKUP_POSTCMD" "${2:-}"
}

function docker_get_db_restore_precmd_from_id {
    docker_get_db_value_id $1 "DB_RESTORE_PRECMD" "${2:-}"
}

function docker_get_db_restore_postcmd_from_id {
    docker_get_db_value_id $1 "DB_RESTORE_POSTCMD" "${2:-}"
}

function docker_run_cmd_in_container {
    local source_container_id=$1
    local cmd="${2:-}"
    if [ ! -z "$cmd" ]
    then
        if docker exec $source_container_id "$cmd"
        then
            echo successfully run precmd_restore=$cmd
        else
            echo failed in running precmd_restore=$cmd
        fi
    else
        echo No cmd specified to run
    fi
}

function get_parameter {
    local parameter="$1"
    local default="${2:-}"
    local key=parameters.${parameter}
    local action=$(shyaml_get_action $key)
    cat ${CONFIG_FILE} | $BIN_SHYAML $action $key "$default"
}

function get_destination_parameter {
    local destination="$1"
    local parameter="$2"
    local default="${3:-}"
    local ENV_VAR="$(get_config_env_var destinations $destination $parameter)"
    if [ -n "${ENV_VAR}" ]; then
        echo ${ENV_VAR}
        return
    fi
    local key=destinations.${destination}.${parameter}
    local action=$(shyaml_get_action $key)
    cat ${CONFIG_FILE} | $BIN_SHYAML $action $key "$default"
}

function get_source_parameter {
    local source="$1"
    local parameter="$2"
    local default="${3:-}"
    local key=sources.${source}.${parameter}
    local action=$(shyaml_get_action $key)
    cat ${CONFIG_FILE} | $BIN_SHYAML $action $key "$default"
}

function get_config_env_var {
    local VAR_PARTS=$(echo $@ | tr '[:lower:]' '[:upper:]' | sed -e 's/[^A-Z0-9_]/_/g')
    VAR_NAME=$(join_by _ CONFIG $VAR_PARTS)
    echo "${!VAR_NAME:-}"
}

function join_by { local IFS="$1"; shift; echo "$*"; }

function dir_is_mounted_from_host {
    local searched_dir=$1
    local container_name=${2:-$(docker_get_current_container_id)}
    local dir_found=$(docker inspect ${container_name} | \
                        underscore extract 0.HostConfig.Binds --outfmt text | \
                        grep ":${searched_dir}:rw")
    if [ -n "${dir_found}" ]
    then
        echo 0
        return
    fi
    echo 1
}

function shyaml_get_action {
    local key=$1
    local type=$(cat ${CONFIG_FILE} | $BIN_SHYAML get-type $key none)
    case $type in
        sequence)
            echo get-values
            ;;
        struct)
            echo get-values
            ;;
        str)
            echo get-value
            ;;
        int)
            echo get-value
            ;;
        bool)
            echo get-value
            ;;
    esac

}
