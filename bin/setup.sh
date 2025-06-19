#!/bin/bash

set -e

source $(dirname $0)/_lib.sh

PROJECT=$1
PROJECT_NAME=$(basename "$PROJECT")
read_config $PROJECT # Fills variables EXTRACT_URLS and CHECK_REF_INTEGRITY

lock_or_exit $PROJECT

# Clean before re-import
rm -fr ${PROJECT}/import/
rm -fr ${PROJECT}/export/update
rm -fr ${PROJECT}/export/state.txt

for EXTRACT_URL in $EXTRACT_URLS; do
    download_pbf $EXTRACT_URL # Fills variables PBF and EXTRACT_NAME

    ope /${PBF} =n | gzip > ${PROJECT}/import/${EXTRACT_NAME}-n.pgcopy.gz
    ope /${PBF} =w | gzip > ${PROJECT}/import/${EXTRACT_NAME}-w.pgcopy.gz
    ope /${PBF} =r | gzip > ${PROJECT}/import/${EXTRACT_NAME}-r.pgcopy.gz
done

check_sequenceNumber ${PROJECT} "${EXTRACT_URLS}"

mkdir -p ${PROJECT}/export/update

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = off;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT_NAME} CASCADE"
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema.sql

zcat ${PROJECT}/import/*-n.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT_NAME}.osm_base_n FROM stdin" || exit 1 &&
zcat ${PROJECT}/import/*-w.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT_NAME}.osm_base_w FROM stdin" || exit 1 &&
zcat ${PROJECT}/import/*-r.pgcopy.gz | sort -k 1,1n -k 2,2nr --unique | psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "COPY ${PROJECT_NAME}.osm_base_r FROM stdin" || exit 1 &&
rm -f ${PROJECT}/import/*.pgcopy.gz

# if CHECK_REF_INTEGRITY not empty
if [ -n "$CHECK_REF_INTEGRITY" ]; then
    psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema-check-integrity.sql
fi
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/schema/schema_changes_geom.sql
psql $DATABASE_URL -v ON_ERROR_STOP=ON -v schema=${PROJECT_NAME} -f lib/time_machine/sql/changes_logs.sql

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "ALTER SYSTEM SET autovacuum = on;" && \
psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "SELECT PG_RELOAD_CONF();"

mkdir -p ${PROJECT}/export
