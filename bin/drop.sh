#!/bin/bash

set -e

PROJECT=$1
PROJECT_NAME=$(basename "$PROJECT")

LOCK=${PROJECT}/lock
touch $LOCK
exec 8>$LOCK;

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT_NAME} CASCADE"

rm -fr ${PROJECT}
