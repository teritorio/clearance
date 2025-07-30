FROM ruby:3.4-bullseye

RUN apt update -y && apt install -y \
    build-essential \
    bzip2 \
    clang \
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
    postgresql-client \
    pyosmium \
    python-is-python3 \
    python3-pyosmium \
    python3-requests \
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

# Custom patch, wating for https://github.com/osmcode/osmium-tool/issues/282
ADD osmium-tool-merge-osc-deleted.diff .
RUN git clone https://github.com/osmcode/osmium-tool.git && \
    cd osmium-tool && \
    git checkout v1.13.0 && \
    patch -p1 < ../osmium-tool-merge-osc-deleted.diff && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make install

WORKDIR /srv/app

ADD Gemfile Gemfile.lock ./
RUN bundle config --global silence_root_warning 1
RUN bundle install

RUN cd /usr/local/bundle/gems/levenshtein-ffi-1.1.0/ext/levenshtein && \
    make

ADD . ./

EXPOSE 9000
