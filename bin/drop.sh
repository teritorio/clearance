#!/bin/bash

set -e

source $(dirname $0)/_lib.sh

PROJECT=$1
project_path # Fills variables PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH

lock_or_wait $PROJECT

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS \"${PROJECT}\" CASCADE"

rm -fr ${PROJECTS_DATA_PATH}/${PROJECT}
