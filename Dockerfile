FROM ruby:3.4-alpine

RUN apk add --no-cache --virtual \
        build-dependencies \
        build-base \
        git \
        libbz2 \
        libpq-dev \
        libffi-dev \
        postgresql-dev \
        proj-dev \
        ruby-dev \
        ruby-json

WORKDIR /srv/app

ADD Gemfile Gemfile.lock ./
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD . ./

EXPOSE 9000
