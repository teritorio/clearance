#!/bin/bash

set -e

source $(dirname $0)/_lib.sh

PROJECT=$1
PROJECT_NAME=$(basename "$PROJECT")

lock_or_wait $PROJECT

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS \"${PROJECT_NAME}\" CASCADE"

rm -fr ${PROJECT}
