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
    osmium-tool \
    osmosis \
    postgresql-client \
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

WORKDIR /srv/app

ADD Gemfile Gemfile.lock ./
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD . ./

RUN apt install -y python-is-python3 python3-pyosmium
