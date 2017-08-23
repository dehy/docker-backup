#!/bin/bash

set -eu

# Methods for C14 cold storage https://www.online.net/en/c14

source /docker-backup-app/libs/http_rest.sh

c14_endpoint="https://api.online.net/api/v1"

c14_safe_id=""
c14_archive_id=""

c14_server=""
c14_port=""
c14_login=""
c14_password=""

http.setEndpoint "${c14_endpoint}"

service.configure() {
    http.addHeader "Authorization" "Bearer $(get_destination_parameter $1 private_token)"
}

# Things to do before backuping data
service.global_pre_backup_hook() {
    return 0
}

# Executed on each worker before backup
service.pre_backup_hook() {
    set -x

    local c14_safe_name="$1"
    local c14_archive_name="$2"
    local c14_archive_description="$3"
    local c14_archive_parity="$4"
    local c14_archive_crypto="$5"
    local c14_archive_platforms="$6"

    local response
    ## Find the c14_safe_id of the safe by the name biven by the user
    # GET /storage/c14/safe
    response=$(http.get '/storage/c14/safe')
    c14_safe_id=$(echo $response | ${BIN_JQ} ".[] | select(.name == \"${c14_safe_name}\").uuid_ref")

    ## Create an archive
    # POST /storage/c14/safe/{c14_safe_id}/archive [name, description, parity, crypto, protocols, platforms]
    local body="{\"name\": \"${c14_archive_name}\", \"description\": \"${c14_archive_description}\", \"parity\": \"${c14_archive_parity}\", \"crypto\": \"${c14_archive_crypto}\", \"protocols\": [\"SSH\"], \"platforms\": ${c14_archive_platforms}}"
    local response=$(http.post "/storage/c14/safe/${c14_safe_id}/archive" "${body}")
    # Is there an error?
    if c14_is_error_response "$response"; then
        # Error code 10 = archive already exists with same name
        if [ "$(c14_get_error_code "$response")" == "10" ]; then
            # Get the c14_archive_id  by its name
            response=$(http.get "/storage/c14/safe/${c14_safe_id}/archive")
            c14_archive_id=$(echo $response | ${BIN_JQ} ".[] | select(.name == \"${c14_archive_name}\").uuid_ref")
        else
            return 1
        fi
    else
        c14_archive_id=$(echo $response | ${BIN_JQ} '.')
    fi

    local c14_archive_is_ready=$(c14_is_archive_ready $c14_safe_id $c14_archive_id)
    while [ $c14_archive_is_ready -eq 0 ]; do
        sleep 5
        c14_archive_is_ready=$(c14_is_archive_ready $c14_safe_id $c14_archive_id)
    done

    local c14_archive_details=$(http.get "/storage/c14/safe/${c14_safe_id}/archive/${c14_archive_id}")
    if c14_is_error_response "$c14_archive_details"; then
        echo $c14_archive_details
        return 1
    fi
    local c14_credential=$(echo $c14_archive_details | ${BIN_JQ} ".bucket.credentials[] | select(.protocol == \"ssh\")")
    c14_login=$(echo $c14_credential | ${BIN_JQ} ".login")
    c14_password=$(echo $c14_credential | ${BIN_JQ} ".password")
    local c14_uri=$(echo $c14_credential | ${BIN_JQ} ".uri")
    local regexp=".*@(.+):([0-9]+)"
    c14_server=$(echo $c14_uri | sed -rn -e "s/${regexp}/\1/p")
    c14_port=$(echo $c14_uri | sed -rn -e "s/${regexp}/\2/p")

    set +x
    # echo "${c14_server}%${c14_port}%${c14_login}%${c14_password}"
    return 0
}

# Executed on each worker after backup, if success
service.post_backup_success_hook() {
    local result=${1:-"success"}

    if [ "$result" == "success" ]; then
        # Archive the archive...
        # POST /storage/c14/safe/{c14_safe_id}/archive/{c14_archive_id}/archive
        http.post "/storage/c14/safe/${c14_safe_id}/archive/${c14_archive_id}/archive"
    fi
}

# Things to do after data has fail to be transfered
service.post_backup_failure_hook() {
    return 0
}

# Executed on each worker after backup, if failure
service.global_post_backup_hook() {
    return 0
}

c14_is_error_response() {
    local response=$1
    if [ "$(echo $response | ${BIN_JQ} '. | objects | has("error")')" == "true" ]; then
        return 0
    fi
    return 1
}
c14_get_error_code() {
    local response=$1
    echo $response | ${BIN_JQ} '.code'

    return $?
}

c14_is_archive_ready() {
    local c14_safe_id=$1
    local c14_archive_id=$2

    local response=$(http.get /storage/c14/safe/${c14_safe_id}/archive/${c14_archive_id})
    local status=$(echo $response | ${BIN_JQ} '.status')
    if [ "$status" == "active" ]; then
        echo 1
        return 0
    fi

    echo 0
}

