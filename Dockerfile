# Node 22 LTS on Debian slim.
# Zeabur injects service env into the image build. NODE_ENV=production makes
# `npm ci` skip devDependencies, then the root postinstall (`patch-package`)
# exits 127 because that binary was never installed. node:26-alpine also has
# no git(1), and libsignal is a GitHub dependency.
FROM node:22-bookworm-slim AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends git openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" \
  && git config --global url."https://github.com/".insteadOf "git@github.com:"

WORKDIR /app

# Build-only. Not copied into the runner image, so it cannot override the
# DATABASE_URL Zeabur injects at runtime. mysql.zeabur.internal is not
# reachable while the image is building; Prisma only needs a syntactically
# valid URL in order to generate the client.
ENV DATABASE_URL="mysql://build:build@127.0.0.1:3306/wa_akg_build"

COPY package.json package-lock.json ./
COPY patches ./patches/
COPY prisma ./prisma/

# --include=dev wins even when Zeabur has injected NODE_ENV=production.
RUN NODE_ENV=development npm ci --legacy-peer-deps --include=dev \
  && npm cache clean --force

COPY . .

RUN npx prisma generate && npm run build

# Runtime still runs Prisma 5 `db push` and starts the server with tsx.
# Both CLIs are devDependencies, so prune removes them. Installing them
# while they remain in devDependencies is a no-op under NODE_ENV=production,
# and `npx prisma` would then download Prisma 8, which cannot push this schema.
RUN npm prune --omit=dev \
  && npm pkg delete scripts.postinstall \
  && npm pkg delete devDependencies \
  && NODE_ENV=production npm install --no-save --legacy-peer-deps prisma@5.22.0 tsx@4.21.0 typescript@5.9.3 \
  && ./node_modules/.bin/prisma generate

FROM node:22-bookworm-slim AS runner

RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/package.json /app/package-lock.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/src ./src
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public
COPY --from=builder /app/tsconfig.json ./
COPY --from=builder /app/next.config.ts ./
COPY --from=builder /app/scripts ./scripts

# Do not set DATABASE_URL in this stage. Zeabur injects the real service
# value into the final stage; a placeholder here would shadow it.
ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
EXPOSE 3000

CMD ["sh", "-c", "./node_modules/.bin/prisma db push && (if [ -n \"$ADMIN_EMAIL\" ] && [ -n \"$ADMIN_PASSWORD\" ]; then node scripts/setup-admin.js \"$ADMIN_EMAIL\" \"$ADMIN_PASSWORD\"; fi) && node node_modules/tsx/dist/cli.mjs src/server/index.ts"]
