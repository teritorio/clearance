FROM ruby:3.0-bullseye

RUN apt update -y && apt install -y \
    build-essential \
    bzip2 \
    cmake \
    gzip \
    libboost-dev \
    libboost-program-options-dev \
    libexpat1-dev \
    libgeos-dev \
    libosmium2-dev \
    libpq-dev \
    libproj-dev \
    libprotozero-dev \
    osmosis \
    postgresql-client \
    python-is-python3 \
    python3-pyosmium \
    ruby-dev \
    ruby-json \
    wget

WORKDIR /srv/

RUN git clone https://github.com/osmcode/osm-postgresql-experiments.git && \
    cd osm-postgresql-experiments && \
    git checkout 3ddc1ca && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make install

WORKDIR /srv/

# Manual install of osmium-tool as we require at least 1.17.0
RUN git clone https://github.com/osmcode/osmium-tool.git && \
    cd osmium-tool && \
    git checkout v1.18.0 && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make install

WORKDIR /srv/app

ADD Gemfile Gemfile.lock ./
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD . ./
