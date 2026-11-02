# syntax=docker/dockerfile:1
FROM nginx:1.28.0-alpine AS runtime
WORKDIR /app
COPY --link nginx.conf.template /etc/nginx/local.conf.template
LABEL org.opencontainers.image.title="Advocacia Online Local HTTPS"
USER 1000:1000
EXPOSE 3443
ENTRYPOINT ["/bin/sh", "-c", "envsubst '${AUTH_INGRESS_SECRET} ${LOCAL_APP_HOST}' < /etc/nginx/local.conf.template > /tmp/nginx.conf && exec nginx -c /tmp/nginx.conf -g 'daemon off;'"]
