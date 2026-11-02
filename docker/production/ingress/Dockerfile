# syntax=docker/dockerfile:1
FROM nginx:1.28.0-alpine AS runtime
WORKDIR /app
COPY --link nginx.conf.template /etc/nginx/advocacia.conf.template
LABEL org.opencontainers.image.title="Advocacia Online Production Ingress" \
      org.opencontainers.image.source="https://github.com/smcruzfilipe/advocaciaonline"
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["/bin/sh", "-ec", ": \"${APP_ORIGIN:?APP_ORIGIN required}\" \"${AUTH_INGRESS_SECRET:?AUTH_INGRESS_SECRET required}\" \"${TRUSTED_PROXY_IP:?TRUSTED_PROXY_IP required}\" \"${WEB_UPSTREAM_HOST:?WEB_UPSTREAM_HOST required}\"; [ \"$APP_ORIGIN\" = https://painel.alessandraguinosa.adv.br ] || { echo 'Invalid APP_ORIGIN' >&2; exit 1; }; [ ${#AUTH_INGRESS_SECRET} -ge 32 ] || { echo 'AUTH_INGRESS_SECRET too short' >&2; exit 1; }; case \"$AUTH_INGRESS_SECRET\" in *[!A-Za-z0-9_-]*) echo 'Invalid AUTH_INGRESS_SECRET characters' >&2; exit 1;; esac; case \"$TRUSTED_PROXY_IP\" in *[!0-9.]*|'') echo 'Invalid TRUSTED_PROXY_IP' >&2; exit 1;; esac; case \"$WEB_UPSTREAM_HOST\" in *[!A-Za-z0-9.-]*|'') echo 'Invalid WEB_UPSTREAM_HOST' >&2; exit 1;; esac; umask 077; envsubst '${AUTH_INGRESS_SECRET} ${TRUSTED_PROXY_IP} ${WEB_UPSTREAM_HOST}' < /etc/nginx/advocacia.conf.template > /tmp/nginx.conf; exec nginx -c /tmp/nginx.conf -g 'daemon off;' "]
