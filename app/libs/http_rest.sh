#!/bin/bash

HTTP_REST_HEADER_CONTENT_TYPE="Content-Type: application/json; charset=utf-8"
# HTTP_REST_HEADER_ACCEPT="Accept: application/json"
HTTP_REST_ENDPOINT=""
declare -A HTTP_REST_HEADERS

BIN_CURL="$(which curl)"

function http.setEndpoint {
    HTTP_REST_ENDPOINT="$1"
}

function http.addHeader {
    HTTP_REST_HEADERS[$1]="$2"
}

function http.get {
    local uri=$1

    eval "${BIN_CURL} -X 'GET' -H \"${HTTP_REST_HEADER_CONTENT_TYPE}\" $(http.getExtraHeaders) ${HTTP_REST_ENDPOINT}${uri}" 2> /dev/null
}

function http.post {
    local uri=$1
    local body=${2:-}

    local cmd="${BIN_CURL} -X 'POST' -H \"${HTTP_REST_HEADER_CONTENT_TYPE}\" $(http.getExtraHeaders) -d \$'${body}' ${HTTP_REST_ENDPOINT}${uri}" 2> /dev/null
    # echo "$cmd"
    # exit
    eval "$cmd"
}

function http.getExtraHeaders {
    local extra_headers=""
    for key in "${!HTTP_REST_HEADERS[@]}"
    do
        extra_headers="${extra_headers} -H \"${key}: ${HTTP_REST_HEADERS[$key]}\""
        # echo "key  : $key"
        # echo "value: ${HTTP_REST_HEADERS[$key]}"
    done

    echo "$extra_headers"
}
