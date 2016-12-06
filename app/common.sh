#!/bin/bash

set -eux

BIN_UNDERSCORE=/usr/local/bin/underscore
BIN_SHYAML=/usr/local/bin/shyaml

CONFIG_FILE="/docker-backup-app/config.yml"

DOCKER_SOCKET="/var/run/docker.sock"
DOCKER_GET="curl -XGET -H 'Accept: application/json' --unix-socket ${DOCKER_SOCKET} http://localhost"
DOCKER_POST="curl -XPOST -H 'Accept: application/json|Content-type: application/json' --unix-socket ${DOCKER_SOCKET} http://localhost"

function check_vitals {
    # TODO: check if config file is present and readable
    # check if /var/run/docker.sock is present and readable
    # Advanced: check config.yml validity
    echo ""
}

function install_docker {
    docker_engine_version=$(eval $DOCKER_GET/version | $BIN_UNDERSCORE select ".Version" --outfmt text)
    # Remove commercialy supported extension
    docker_engine_version=$(echo $docker_engine_version | sed -E 's/-cs[0-9]+$//')
    local docker_engine_package_version=$(apt-cache madison docker-engine | grep ${docker_engine_version} | awk -F "|" '{ print $2 }' | tr -d " ")
    apt-get install -y --no-install-recommends docker-engine=${docker_engine_package_version}
}

function docker_get {
    local url_path="${1:-/}"
    eval ${DOCKER_GET}${url_path}
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
    local VAR_PARTS=$(echo $@ | tr '[:lower:]' '[:upper:]')
    VAR_NAME=$(join_by _ CONFIG $VAR_PARTS)
    echo "${!VAR_NAME:-}"
}

function join_by { local IFS="$1"; shift; echo "$*"; }

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
    esac

}
