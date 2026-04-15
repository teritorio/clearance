#!/bin/bash

set -eu

source $(dirname $0)/_lib.sh

projects_path # Fills variables PROJECTS, PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH

PROJECT=$1

lock_or_wait $PROJECT

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS \"${PROJECT}\" CASCADE"

rm -fr ${PROJECTS_DATA_PATH}/${PROJECT}
