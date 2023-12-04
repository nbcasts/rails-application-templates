# frozen_string_literal: true

gem "awesome_print"
gem "tailwindcss-rails" unless options["css"] == "tailwind"
gem "phlex-rails"

gem_group :development do
  gem "guard-livereload", require: false
  gem "rubocop"
end

gem_group :development, :test do
  gem "rspec-rails"
end

file "mkdir spec/suite/a_spec.rb", <<~CODE
  # frozen_string_literal: true

  require "rails_helper"

  RSpec.describe "Something" do
    it "does something" do
      expect(true).to eq(true)
    end
  end
CODE

file ".rubocop.yml", <<~CODE
  ---

  require:
  - rubocop-rails
  - rubocop-rake

  AllCops:
    NewCops: enable
    ExtraDetails: false
    Exclude:
    - ".git/**/*"
    - bin/**/*
    - tmp/**/*
    - sandbox/**/*
    - sandbox/**/*
    - db/**/*.rb

  Layout/HashAlignment:
    EnforcedColonStyle: table
    EnforcedHashRocketStyle: table

  Layout/LineLength:
    Exclude:
    - app/views/**/*

  Lint/MissingSuper:
    Enabled: false

  Metrics/AbcSize:
    Exclude:
    - app/views/**/*.rb
    - db/migrate/**/*.rb

  Metrics/BlockLength:
    Enabled: false

  Metrics/MethodLength:
    Exclude:
    - app/views/**/*.rb

  Rails/Output:
    Exclude:
    - app/views/**/*.rb

  Rails/RakeEnvironment:
    Enabled: false

  Style/AccessorGrouping:
    EnforcedStyle: separated

  Style/BlockDelimiters:
    EnforcedStyle: semantic
    Exclude:
    - app/views/**/*
    BracesRequiredMethods:
    - let
    - let!

  Style/Documentation:
    Enabled: false

  Style/EmptyMethod:
    EnforcedStyle: expanded

  Style/FrozenStringLiteralComment:
    Enabled: true
    SafeAutoCorrect: true

  Style/HashSyntax:
    EnforcedShorthandSyntax: never

  Style/KeywordParametersOrder:
    Enabled: false

  Style/RedundantInitialize:
    Exclude:
    - app/views/**/*.rb

  Style/StringLiterals:
    EnforcedStyle: double_quotes

  Style/TrailingCommaInArguments:
    Enabled: false

  Style/TrailingCommaInArrayLiteral:
    Enabled: false

  Style/TrailingCommaInHashLiteral:
    EnforcedStyleForMultiline: consistent_comma

  Style/TrivialAccessors:
    Enabled: false
CODE

file "docker-compose.yml", <<~CODE
  ---
  version: "3.7"

  x-build-common: &build-common
    build:
      context: .
      dockerfile: Dockerfile
      target: development

  x-app-common: &app-common
    extra_hosts:
      - "host.docker.internal:host-gateway"
    stdin_open: true
    tty: true
    volumes:
      - .:/app
      - bundler:/bundler

  services:
    web:
      <<: [*build-common, *app-common]
      depends_on:
        - tailwind
      command: bundle exec rails s -b 0.0.0.0
      ports:
        - "3000:3000"
      environment:
        ENVIRONMENT: development
        HISTFILE: /app/.zsh_history
        REDIS_URL: redis://redis:6379/0

    guard:
      <<: [*build-common, *app-common]
      depends_on:
        - web
      command: bundle exec guard
      ports:
        - "35729:35729"

    tailwind:
      <<: [*build-common, *app-common]
      command: bundle exec bin/rails tailwindcss:watch
      environment:
        REDIS_URL: redis://redis:6379/0
  #{' '}
    redis:
      image: redis:latest
      volumes:
        - redis-data:/data
      ports:
        - '6379:6379'

  volumes:
    bundler:
    mailhog:
    redis-data:
CODE

file "Dockerfile", <<~CODE
  ARG APP_ROOT=/app
  ARG BUNDLE_PATH=/bundler
  ARG PACKAGES_RUNTIME="tzdata"
  ARG RUBY_VERSION=3.2.2

  ################################################################################
  # Base configuration
  #
  FROM ruby:$RUBY_VERSION-slim-bullseye AS builder-base
  ARG APP_ROOT
  ARG BUNDLE_PATH
  ARG PACKAGES_BUILD="build-essential git libxml2-dev libpq-dev"

  ENV BUNDLE_PATH=$BUNDLE_PATH
  ENV BUNDLE_BIN="$BUNDLE_PATH/bin"
  ENV PATH="$BUNDLE_BIN:$PATH"

  WORKDIR $APP_ROOT

  RUN apt-get update && apt-get upgrade -y && \
      apt-get install -y --no-install-recommends $PACKAGES_BUILD && \
      apt-get clean && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/* /tmp/* /var/tmp/*

  COPY Gemfile Gemfile.lock $APP_ROOT/
  RUN gem install bundler --no-document # -v $(grep -A1 'BUNDLED WITH' Gemfile.lock | tail -1 | xargs)

  ################################################################################
  # Development image
  #
  FROM builder-base AS development
  ARG GEMS_DEV="pessimizer"
  ARG PACKAGES_DEV="zsh curl wget sudo"
  ARG PACKAGES_RUNTIME
  ARG USERNAME=developer
  ARG USER_UID=1000
  ARG USER_GID=$USER_UID

  RUN apt-get update && apt-get upgrade -y && \
      apt-get install -y --no-install-recommends $PACKAGES_DEV $PACKAGES_RUNTIME && \
      apt-get clean && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
      gem install $GEMS_DEV && \
      addgroup --gid $USER_GID $USERNAME && \
      adduser --home /home/$USERNAME --shell /bin/zsh --uid $USER_UID --gid $USER_GID $USERNAME && \
      echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME && \
      mkdir -p $BUNDLE_PATH && \
      chown -R $USERNAME:$USERNAME $BUNDLE_PATH && \
      chown -R $USERNAME:$USERNAME $APP_ROOT

  USER $USERNAME

  RUN bundle install --jobs 4 --retry 3

  WORKDIR /home/$USERNAME
  RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.1.2/zsh-in-docker.sh)"
  WORKDIR $APP_ROOT
CODE

file "script/docker-entrypoint-development.sh", <<~CODE
  #!/bin/sh

  set -e

  if [ -f tmp/pids/server.pid ]; then
    rm tmp/pids/server.pid
  fi

  script/wait-for-it.sh database:5432

  bundle check || bundle install

  exec "$@"
CODE

after_bundle do
  rails_command "tailwindcss:install"
  rails_command "generate rspec:install"
  rails_command "turbo:install:redis"
  rails_command "generate phlex:install"
end

# This goes last
after_bundle do
  git :init
  git add: "."
  git commit: %( -m 'Initial commit' )
end
