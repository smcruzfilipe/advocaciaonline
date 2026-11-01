# syntax=docker/dockerfile:1
# Local validation only. Deployment uses the existing PostgreSQL instance.
FROM postgres:18.6-alpine3.23 AS runtime
WORKDIR /var/lib/postgresql
RUN mkdir -p /var/lib/postgresql/18/docker \
    && chown -R 70:70 /var/lib/postgresql \
    && chmod 0700 /var/lib/postgresql/18/docker
COPY --link db/provision.sql /docker-entrypoint-initdb.d/10-identity.sql
COPY --link db/provision_despachante.sql /docker-entrypoint-initdb.d/20-despachante.sql
COPY --link db/provision_processador.sql /docker-entrypoint-initdb.d/30-processador.sql
COPY --link docker/local-passwords.sql /docker-entrypoint-initdb.d/40-passwords.sql
LABEL org.opencontainers.image.title="Advocacia Online Local PostgreSQL" \
      org.opencontainers.image.description="Non-root PostgreSQL for local validation, never deployment"
USER 70:70
