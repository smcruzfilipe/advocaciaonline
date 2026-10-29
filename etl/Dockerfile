# syntax=docker/dockerfile:1
FROM ruby:4.0.9-alpine3.23 AS base
WORKDIR /app
RUN apk add --no-cache libpq tzdata \
    && addgroup -g 1000 app \
    && adduser -D -u 1000 -G app app \
    && mkdir -p /bundle /app/tmp \
    && chown -R 1000:1000 /bundle /app
ENV BUNDLE_PATH=/bundle \
    BUNDLE_FROZEN=true \
    BUNDLE_DEPLOYMENT=true \
    HOME=/home/app
USER 1000:1000

FROM base AS dependencies
USER root
RUN apk add --no-cache build-base postgresql-dev
USER 1000:1000
COPY --link --chown=1000:1000 Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 \
    && rm -rf /bundle/ruby/*/cache /bundle/ruby/*/bundler/gems/*/.git

FROM dependencies AS production_dependencies
ENV BUNDLE_WITHOUT=test
RUN bundle clean --force

FROM base AS test
COPY --link --from=dependencies --chown=1000:1000 /bundle /bundle
COPY --link --chown=1000:1000 Gemfile Gemfile.lock ./
COPY --link --chown=1000:1000 lib ./lib
COPY --link --chown=1000:1000 test ./test
USER 1000:1000
CMD ["bundle", "exec", "ruby", "-Itest", "-e", "Dir['test/*_test.rb'].sort.each { |file| require_relative file }"]

FROM base AS runtime
ENV BUNDLE_WITHOUT=test
COPY --link --from=production_dependencies --chown=1000:1000 /bundle /bundle
COPY --link --chown=1000:1000 Gemfile Gemfile.lock ./
COPY --link --chown=1000:1000 lib ./lib
COPY --link --chown=1000:1000 --chmod=0555 bin ./bin
LABEL org.opencontainers.image.title="Advocacia Online Processador" \
      org.opencontainers.image.description="Processamento DJEN com acesso PostgreSQL restrito por trabalho"
USER 1000:1000
CMD ["bundle", "exec", "ruby", "bin/processador"]

