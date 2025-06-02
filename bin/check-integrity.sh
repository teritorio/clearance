#!/bin/bash

set -e

PROJECT=$1

LOCK=${PROJECT}/lock
touch $LOCK
exec 8>$LOCK;

# Update OSM extracts
IMPORT=${PROJECT}/import
EXTRACTS=$(find ${IMPORT}/ -name '*.osm.pbf')

for EXTRACT in $EXTRACTS; do
    echo "Updating OSM extract: $EXTRACT"
    pyosmium-up-to-date "$EXTRACT" || (echo "Extract $EXTRACT fails to update, abort" && exit 1)
done

# Merge OSM extracts
echo "Merging OSM extracts..."
IMPORT_MERGE=$IMPORT/../merge.osm.pbf
osmium merge $EXTRACTS --overwrite --output $IMPORT_MERGE || (echo "osmium merge fails, cleaning and abort..." && rm -f $IMPORT/merge.osm.pbf && exit 1)

# Dump Clearance data
echo "Dumping Clearance data..."
EXPORT=${PROJECT}/export/$(basename $PROJECT).osm.pbf
$(dirname $0)/dump.sh ${PROJECT}

# Update Clearance Dump with Clearance retained data
echo "Dump Clearance retained data..."
RETAINED=${EXPORT%.osm.pbf}-retained.osc.gz
EXPORT_WITH_RETAINED=${EXPORT%.osm.pbf}-with_retained.osm.pbf
bundle exec ruby lib/time_machine/main.rb --project=/${PROJECT} --export-retained-diff=${RETAINED}
osmium apply-changes ${EXPORT} ${RETAINED} --overwrite -o ${EXPORT_WITH_RETAINED} || (echo "osmium apply-changes fails" && exit 1)

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
