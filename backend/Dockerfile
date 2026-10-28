# syntax=docker/dockerfile:1
FROM ruby:4.0.9-alpine3.23 AS base
WORKDIR /app
RUN apk add --no-cache libpq libstdc++ yaml tzdata \
    && addgroup -g 1000 app \
    && adduser -D -u 1000 -G app app \
    && mkdir -p /bundle /app/tmp /app/log \
    && chown -R 1000:1000 /bundle /app
ENV BUNDLE_PATH=/bundle \
    BUNDLE_FROZEN=true \
    BUNDLE_DEPLOYMENT=true \
    HOME=/home/app
USER 1000:1000

FROM base AS dependencies
USER root
RUN apk add --no-cache build-base postgresql-dev yaml-dev
USER 1000:1000
COPY --link --chown=1000:1000 Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 \
    && rm -rf /bundle/ruby/*/cache /bundle/ruby/*/bundler/gems/*/.git

FROM dependencies AS production_dependencies
ENV BUNDLE_WITHOUT=test
RUN bundle clean --force

FROM base AS application
ENV RAILS_ENV=production \
    BUNDLE_WITHOUT=test \
    PORT=3000
COPY --link --from=production_dependencies --chown=1000:1000 /bundle /bundle
COPY --link --chown=1000:1000 Gemfile Gemfile.lock Rakefile config.ru ./
COPY --link --chown=1000:1000 app ./app
COPY --link --chown=1000:1000 config ./config
COPY --link --chown=1000:1000 db ./db
COPY --link --chown=1000:1000 --chmod=0555 bin ./bin
LABEL org.opencontainers.image.title="Advocacia Online Rails API" \
      org.opencontainers.image.description="API-only Rails with server-side OIDC sessions and PostgreSQL tenant RLS"
EXPOSE 3000
USER 1000:1000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

# This target adds test code/dependencies without adding compilers to runtime.
FROM application AS test
ENV RAILS_ENV=test BUNDLE_WITHOUT="" BUNDLE_GEMFILE=/app/Gemfile
COPY --link --from=dependencies --chown=1000:1000 /bundle /bundle
COPY --link --chown=1000:1000 test ./test
COPY --link --chown=1000:1000 planner ./planner
CMD ["ruby", "bin/rails", "test"]

FROM ruby:4.0.9-alpine3.23 AS planner_base
WORKDIR /app
RUN apk add --no-cache libpq tzdata \
    && addgroup -g 1000 app \
    && adduser -D -u 1000 -G app app \
    && mkdir -p /bundle /app/planner \
    && chown -R 1000:1000 /bundle /app
ENV BUNDLE_PATH=/bundle \
    BUNDLE_FROZEN=true \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_GEMFILE=/app/planner/Gemfile \
    HOME=/home/app
USER 1000:1000

FROM planner_base AS planner_dependencies
USER root
RUN apk add --no-cache build-base postgresql-dev
USER 1000:1000
COPY --link --chown=1000:1000 planner/Gemfile planner/Gemfile.lock ./planner/
RUN bundle install --jobs 4 \
    && rm -rf /bundle/ruby/*/cache /bundle/ruby/*/bundler/gems/*/.git

FROM planner_base AS planner
COPY --link --from=planner_dependencies --chown=1000:1000 /bundle /bundle
COPY --link --chown=1000:1000 planner ./planner
COPY --link --chown=1000:1000 app/services/court_catalog.rb ./app/services/court_catalog.rb
LABEL org.opencontainers.image.title="Advocacia Online Collection Planner" \
      org.opencontainers.image.description="Standalone collection planning with an isolated PostgreSQL login"
USER 1000:1000
CMD ["ruby", "planner/run.rb"]

FROM application AS runtime
