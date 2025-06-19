function lock_or_exit {
    local PROJECT=$1

    exec {LOCK_FD}> ${PROJECT}/lock
    if ! flock --nonblock $LOCK_FD; then
        echo "${PROJECT} already locked, abort"
        exit 1
    fi
}

function lock_or_wait {
    local PROJECT=$1

    LOCK=${PROJECT}/lock
    touch $LOCK
    exec 8>$LOCK;
}

function read_config {
    local PROJECT=$1

    local CONFIG=${PROJECT}/config.yaml
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

        local GEOFABRIK_COOKIE=${PROJECT}/geofabrik.cookie
        touch ${GEOFABRIK_COOKIE}
        WGET_OPS="--load-cookies ${GEOFABRIK_COOKIE} --max-redirect 0"
        PYOSMIUM_OPS="--cookie ${GEOFABRIK_COOKIE}"

        wget ${WGET_OPS} --quiet https://osm-internal.download.geofabrik.de/cookie_status -O /dev/null \
        || (
            oauth_cookie_client.py \
                --password "${OSM_GEOFABRIK_PASSWORD}" \
                --user "${OSM_GEOFABRIK_USER}" \
                --format netscape \
                --output "${GEOFABRIK_COOKIE}" \
                --osm-host "https://www.openstreetmap.org" \
                --consumer-url "https://osm-internal.download.geofabrik.de/get_cookie"
        ) || (echo "Fails to get geofabrik cookie, abort" && exit 1)
    fi

    # Fills variables WGET_OPS and PYOSMIUM_OPS
}

function download_pbf {
    local EXTRACT_URL=$1

    EXTRACT_NAME=$(basename "$EXTRACT_URL")
    EXTRACT_NAME=${EXTRACT_NAME/-internal/}
    IMPORT=${PROJECT}/import/${EXTRACT_NAME/-latest.osm.pbf/}

    PBF=${IMPORT}/import.osm.pbf

    mkdir -p ${IMPORT}
    geofabrik_cookie ${EXTRACT_URL} # Fills variables WGET_OPS and PYOSMIUM_OPS
    if [ ! -e "${PBF}" ]; then
        wget ${WGET_OPS} ${EXTRACT_URL} --no-clobber -O ${PBF} || (echo "Fails download $EXTRACT, abort" && exit 1)
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

    local STATES=$(find ${PROJECT}/import/ -wholename "*/replication/state.txt")

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

    cp "$(echo ${STATES} | cut -d ' ' -f1)" ${PROJECT}/import/state.txt
    cat ${PROJECT}/import/state.txt
}
