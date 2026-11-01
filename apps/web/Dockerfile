# syntax=docker/dockerfile:1
FROM node:24.22.1-alpine AS build
WORKDIR /app
RUN chown node:node /app
USER node
COPY --link --chown=1000:1000 package.json package-lock.json .npmrc ./
RUN --mount=type=cache,target=/home/node/.npm,uid=1000,gid=1000 npm ci --ignore-scripts
COPY --link --chown=1000:1000 next.config.ts next-env.d.ts tsconfig.json ./
COPY --link --chown=1000:1000 src ./src
RUN npm run build

FROM node:24.22.1-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
COPY --link --from=build --chown=1000:1000 /app/.next/standalone ./
COPY --link --from=build --chown=1000:1000 /app/.next/static ./.next/static
# Package managers are not needed by the standalone server.
RUN rm -rf /usr/local/lib/node_modules /opt/yarn* /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/yarn /usr/local/bin/yarnpkg
LABEL org.opencontainers.image.title="Advocacia Online Web" \
      org.opencontainers.image.description="Next.js standalone runtime without build tools or development dependencies"
USER 1000:1000
EXPOSE 3000
CMD ["node", "server.js"]
