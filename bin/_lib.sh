function lock_or_exit {
    local PROJECT=$1

    mkdir -p ${PROJECTS_DATA_PATH}/${PROJECT}
    exec {LOCK_FD}> ${PROJECTS_DATA_PATH}/${PROJECT}/lock
    if ! flock --nonblock $LOCK_FD; then
        echo "${PROJECTS_DATA_PATH}/${PROJECT} already locked, abort"
        exit 1
    fi
}

function lock_or_wait {
    local PROJECT=$1

    mkdir -p ${PROJECTS_DATA_PATH}/${PROJECT}
    LOCK=${PROJECTS_DATA_PATH}/${PROJECT}/lock
    touch $LOCK
    exec 8>$LOCK;
}

function project_path {
    PROJECTS_CONFIG_PATH=${PROJECTS_CONFIG_PATH:-projects_config}
    PROJECTS_DATA_PATH=${PROJECTS_DATA_PATH:-projects_data}

    # Fills variables PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH
}

function read_config {
    local PROJECT=$1

    local CONFIG=${PROJECTS_CONFIG_PATH}/${PROJECT}/config.yaml
    EXTRACT_URLS=`cat ${CONFIG} | ruby -ryaml -e "puts YAML.load(STDIN).dig('import', 'extracts')&.join(' ')"`
    CHECK_REF_INTEGRITY=`cat ${CONFIG} | ruby -ryaml -e "puts YAML.load(STDIN).dig('import', 'check_ref_integrity') == 'true' || ''"`

    # Fills variables EXTRACT_URLS and CHECK_REF_INTEGRITY
}

function geofabrik_cookie {
    if [[ "$1" == *"osm-internal.download.geofabrik.de"* ]]; then
        if [ -z "${OSM_GEOFABRIK_USER}" ] || [ -z "${OSM_GEOFABRIK_PASSWORD}" ]; then
            echo "OSM_GEOFABRIK_USER and OSM_GEOFABRIK_PASSWORD must be set to download from osm-internal.download.geofabrik.de"
            exit 1
        fi

        local GEOFABRIK_COOKIE=${PROJECTS_DATA_PATH}/${PROJECT}/../geofabrik.cookie
        WGET_OPS="--load-cookies ${GEOFABRIK_COOKIE}"
        PYOSMIUM_OPS="--cookie ${GEOFABRIK_COOKIE}"

        local HAS_VALID_COOKIE=99
        if [ -s "${GEOFABRIK_COOKIE}" ]; then
            wget ${WGET_OPS} https://osm-internal.download.geofabrik.de/cookie_status -O /dev/null && HAS_VALID_COOKIE=0 || HAS_VALID_COOKIE=98
        fi

        if [ "${HAS_VALID_COOKIE}" -ne "0" ]; then
            echo "# Get new Geofabrik cookie"
            rm -fr "${GEOFABRIK_COOKIE}"

            python bin/oauth_cookie_client.py \
                --password "${OSM_GEOFABRIK_PASSWORD}" \
                --user "${OSM_GEOFABRIK_USER}" \
                --format netscape \
                --output "${GEOFABRIK_COOKIE}" \
                --osm-host "https://www.openstreetmap.org" \
                --consumer-url "https://osm-internal.download.geofabrik.de/get_cookie" \
            && (echo "Got a cookie") || (echo "Fails to get geofabrik cookie, abort" && exit 1)
        fi
    fi

    # Fills variables WGET_OPS and PYOSMIUM_OPS
}

function download_pbf {
    local EXTRACT_URL=$1

    EXTRACT_NAME=$(basename "$EXTRACT_URL")
    EXTRACT_NAME=${EXTRACT_NAME/-internal/}
    IMPORT=${PROJECTS_DATA_PATH}/${PROJECT}/import/${EXTRACT_NAME/-latest.osm.pbf/}

    PBF=${IMPORT}/import.osm.pbf

    mkdir -p ${IMPORT}
    geofabrik_cookie ${EXTRACT_URL} # Fills variables WGET_OPS and PYOSMIUM_OPS
    if [ ! -e "${PBF}" ]; then
        wget ${WGET_OPS} ${EXTRACT_URL} --no-clobber -O ${PBF} || (echo "Fails download $EXTRACT_URL, abort" && exit 1)
    fi

    rm -fr ${IMPORT}/replication
    mkdir -p ${IMPORT}/replication
    python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_base_url'))" > ${IMPORT}/replication/sequence.url
    local SEQUENCE_NUMBER=$(python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_sequence_number'))")
    echo $SEQUENCE_NUMBER > ${IMPORT}/replication/sequence.txt
    local TIMESTAMP=$(python -c "import osmium; print(osmium.io.Reader('${PBF}', osmium.osm.osm_entity_bits.NOTHING).header().get('osmosis_replication_timestamp'))")
    echo "sequenceNumber=${SEQUENCE_NUMBER}
timestamp=${TIMESTAMP}" > ${IMPORT}/replication/state.txt

    # Fills variables PBF and EXTRACT_NAME (also WGET_OPS and PYOSMIUM_OPS)
}

function check_sequenceNumber {
    local PROJECT=$1
    local EXTRACTS=$2

    local STATES=$(find ${PROJECTS_DATA_PATH}/${PROJECT}/import/ -wholename "*/replication/state.txt")

    echo "# Check all extracts have the same sequenceNumber"
    if [ "$(echo $STATES | wc -w)" != "$(echo $EXTRACTS | wc -w)" ]; then
        echo "Missing states files. Abort."
        exit 1
    fi
    local COUNT_SEQUENCE_NUMBER=$(echo "$STATES" | grep --no-filename sequenceNumber | sort | uniq | wc -l)
    if [ $COUNT_SEQUENCE_NUMBER -gt 1 ]; then
        echo "Different sequenceNumber from state.txt files. Abort."
        exit 2
    fi

    cp "$(echo ${STATES} | cut -d ' ' -f1)" ${PROJECTS_DATA_PATH}/${PROJECT}/import/state.txt
    cat ${PROJECTS_DATA_PATH}/${PROJECT}/import/state.txt
}
