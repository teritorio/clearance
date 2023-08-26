# Stage 1

FROM alpine:edge AS builder
# No version because:
# - protozero-dev, only on edge
# - libosmium-dev, only on edge/testing

# Package libosmium-dev still in testing
# FROM alpine:testing

RUN apk update && apk add \
        git \
        build-base \
        gcc \
        g++ \
        cmake \
        boost-dev \
        protozero-dev \
        expat-dev

RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing libosmium-dev

RUN git clone https://github.com/osmcode/osm-postgresql-experiments.git && \
    cd osm-postgresql-experiments && \
    git checkout 3ddc1ca && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make


# Stage 2

FROM alpine:edge

RUN apk update && apk add \
        boost \
        protozero \
        expat

COPY --from=builder /osm-postgresql-experiments/build/src/ope /usr/bin/
