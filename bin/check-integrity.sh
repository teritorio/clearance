#!/bin/bash

set -e

source $(dirname $0)/_lib.sh

PROJECT=$1
read_config $PROJECT # Fills variables EXTRACT_URLS and CHECK_REF_INTEGRITY

lock_or_wait $PROJECT

# Update OSM extracts
PBFS=

for EXTRACT_URL in $EXTRACT_URLS; do
    download_pbf $EXTRACT_URL  # Fills variables PBF and EXTRACT_NAME (also WGET_OPS and PYOSMIUM_OPS)

    echo "Updating OSM extract: $EXTRACT"
    pyosmium-up-to-date ${PYOSMIUM_OPS} -v "$PBF" || (echo "Extract $EXTRACT fails to update, abort" && exit 1)

    PBFS="$PBFS $PBF"
done

# Merge OSM extracts
echo "Merging OSM extracts..."
IMPORT_MERGE=$IMPORT/../merge.osm.pbf
osmium merge $PBFS --overwrite --output $IMPORT_MERGE || (echo "osmium merge fails, cleaning and abort..." && rm -f $IMPORT/merge.osm.pbf && exit 2)

osmium check-refs $IMPORT_MERGE || (echo "osmium check-refs fails on $IMPORT_MERGE" && exit 3)

# Dump Clearance data
echo "Dumping Clearance data..."
EXPORT=${PROJECT}/export/$(basename $PROJECT).osm.pbf
$(dirname $0)/dump.sh ${PROJECT}

osmium check-refs $EXPORT || (echo "osmium check-refs fails on $EXPORT" && exit 10)

# Update Clearance Dump with Clearance retained data
echo "Dump Clearance retained data..."
RETAINED=${EXPORT%.osm.pbf}-retained.osc.gz
EXPORT_WITH_RETAINED=${EXPORT%.osm.pbf}-with_retained.osm.pbf
bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --export-retained-diff=${RETAINED}
osmium apply-changes ${EXPORT} ${RETAINED} --overwrite -o ${EXPORT_WITH_RETAINED} || (echo "osmium apply-changes fails" && exit 11)

osmium check-refs $EXPORT_WITH_RETAINED || (echo "osmium check-refs fails on $EXPORT_WITH_RETAINED" && exit 12)

# Compare
# Note, osmium diff does not work as expected, so use osmium derive-changes instead
DIFF=${EXPORT_WITH_RETAINED%.osm.pbf}.osc.gz
osmium derive-changes $IMPORT_MERGE $EXPORT_WITH_RETAINED --overwrite -o $DIFF

if [[ $(find $DIFF -type f -size +110c) ]]; then
    echo "FAILS: OSM extracts are not in sync with the Clearence export."
    exit 99
else
    echo "OK: OSM extracts are in sync with the export."
    rm -f $IMPORT_MERGE $EXPORT_WITH_RETAINED $RETAINED $DIFF
fi
