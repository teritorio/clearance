
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

        wget -v ${WGET_OPS} https://osm-internal.download.geofabrik.de/cookie_status -O /dev/null \
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
