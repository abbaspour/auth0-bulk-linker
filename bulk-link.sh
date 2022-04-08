#!/usr/bin/env bash

set -eo pipefail

declare input_file=''
declare -i job_max=1

command -v awk >/dev/null       || { echo >&2 "ERROR: awk not found."; exit 3; }
command -v jq >/dev/null        || { echo >&2 "ERROR: jq not found."; exit 3; }
command -v base64 >/dev/null    || { echo >&2 "ERROR: base64 not found."; exit 3; }
command -v parallel >/dev/null  || { echo >&2 "ERROR: parallel not found."; exit 3; }

export retries=100

function usage() {
    cat <<END >&2
USAGE: $0 [-e env] [-a access_token] [-c connection_id] [-i input-folder] [-o output-folder] [-v|-h]
        -e file     # .env file location (default cwd)
        -a token    # access_token. default from environment variable
        -c id       # connection_id
        -j count    # parallel job count. defaults to ${job_max}
        -i file     # input CSV file
        -r count    # retry count on HTTP and rate-limit errors with exponential backoff. default in ${retries}
        -h|?        # usage
        -v          # verbose

eg,
     $0 -i users.csv -j8
END
    exit $1
}

while getopts "e:a:i:j:r:hv?" opt
do
    case ${opt} in
        e) source "${OPTARG}";;
        a) access_token=${OPTARG};;
        j) job_max=${OPTARG};;
        i) input_file=${OPTARG};;
        r) retries=${OPTARG};;
        v) set -x;;
        h|?) usage 0;;
        *) usage 1;;
    esac
done

#[[ -z "${access_token}" ]] && { echo >&2 "ERROR: access_token undefined. export access_token='PASTE' "; usage 1; }
[[ -z "${input_file}" ]] && { echo >&2 "ERROR: input_file undefined."; usage 1; }

export AUTH0_DOMAIN_URL=$(echo "${access_token}" | awk -F. '{print $2}' | base64 -di 2>/dev/null | jq -r '.iss')

function link() {
    # shellcheck disable=SC2206
    local row=(${1//,/ })

    local primary_userId=${row[0]}
    # shellcheck disable=SC2206
    local secondary_userId=(${row[1]//|/ })

    local -r BODY=$(printf '{"provider":"%s","user_id":"%s"}'  "${secondary_userId[0]}" "${secondary_userId[1]}")

    #echo $BODY
    curl -s --request POST \
      -H "Authorization: Bearer ${access_token}" \
      --url "${AUTH0_DOMAIN_URL}api/v2/users/${primary_userId}/identities" \
      --header 'content-type: application/json' \
      --retry ${retries} \
      --data "${BODY}"
}

export -f link
export access_token

cat "${input_file}" | parallel -j${job_max} link {}
