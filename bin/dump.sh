#!/bin/bash

set -eu

source $(dirname $0)/_lib.sh
projects_path # Fills variables PROJECTS, PROJECTS_CONFIG_PATH and PROJECTS_DATA_PATH

PROJECT=$1

mkdir -p ${PROJECTS_DATA_PATH}/${PROJECT}/export
bundle exec ruby lib/time_machine/main.rb --project=${PROJECT} --export-osm || exit 1
