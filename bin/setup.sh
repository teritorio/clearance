#!/bin/bash

set -e

source $(dirname $0)/_lib.sh

PROJECT=$1
project_path # Fills variables PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH
read_config $PROJECT # Fills variables EXTRACT_URLS and CHECK_REF_INTEGRITY

lock_or_exit $PROJECT

# Clean before re-import
rm -fr ${PROJECTS_DATA_PATH}/${PROJECT}/import/
rm -fr ${PROJECTS_DATA_PATH}/${PROJECT}/export/update
rm -fr ${PROJECTS_DATA_PATH}/${PROJECT}/export/state.txt

for EXTRACT_URL in $EXTRACT_URLS; do
    download_pbf $EXTRACT_URL # Fills variables PBF and EXTRACT_NAME

    ope /${PBF} =n | gzip > ${PROJECTS_DATA_PATH}/${PROJECT}/import/${EXTRACT_NAME}-n.pgcopy.gz
    ope /${PBF} =w | gzip > ${PROJECTS_DATA_PATH}/${PROJECT}/import/${EXTRACT_NAME}-w.pgcopy.gz
    ope /${PBF} =r | gzip > ${PROJECTS_DATA_PATH}/${PROJECT}/import/${EXTRACT_NAME}-r.pgcopy.gz
done

check_sequenceNumber ${PROJECT} "${EXTRACT_URLS}"

mkdir -p ${PROJECTS_DATA_PATH}/${PROJECT}/export/update

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = off;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS \"${PROJECT}\" CASCADE"
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=\"${PROJECT}\" -f lib/time_machine/sql/schema/schema.sql

zcat ${PROJECTS_DATA_PATH}/${PROJECT}/import/*-n.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY \"${PROJECT}\".osm_base_n FROM stdin" || exit 1 &&
zcat ${PROJECTS_DATA_PATH}/${PROJECT}/import/*-w.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY \"${PROJECT}\".osm_base_w FROM stdin" || exit 1 &&
zcat ${PROJECTS_DATA_PATH}/${PROJECT}/import/*-r.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY \"${PROJECT}\".osm_base_r FROM stdin" || exit 1 &&
rm -f ${PROJECTS_DATA_PATH}/${PROJECT}/import/*.pgcopy.gz

# if CHECK_REF_INTEGRITY not empty
if [ -n "$CHECK_REF_INTEGRITY" ]; then
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=\"${PROJECT}\" -f lib/time_machine/sql/schema/schema-check-integrity.sql
fi
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=\"${PROJECT}\" -f lib/time_machine/sql/schema/schema_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=\"${PROJECT}\" -f lib/time_machine/sql/schema/schema_changes_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=\"${PROJECT}\" -f lib/time_machine/sql/changes_logs.sql

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = on;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

mkdir -p ${PROJECTS_DATA_PATH}/${PROJECT}/export
