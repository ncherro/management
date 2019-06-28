FROM ruby:2.5-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
  jq

ENV APP_HOME /app
ENV LANG C.UTF-8

RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

COPY ./Gemfile* ./

RUN gem install bundler \
  && bundle install

COPY . .

ENTRYPOINT "./run.sh"
