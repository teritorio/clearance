#!/bin/bash

set -e

PROJECT=$1

LOCK=projects/${PROJECT}/lock
touch $LOCK
exec 8>$LOCK;

psql $DATABASE_URL -v ON_ERROR_STOP=ON -c "DROP SCHEMA IF EXISTS ${PROJECT} CASCADE"

rm -fr projects/${PROJECT}
