# syntax=docker/dockerfile:1
# check=error=true

# Production image for pito (local-first self-host). Built multi-arch
# (amd64 + arm64) on Alpine/musl and published to ghcr.io/gmrdad82/pito by
# .github/workflows/release.yml on each version tag; self-hosters pull it via
# docker compose — they never build from source (see docker-compose.yml and
# script/install.sh).
#
# Size discipline (0.7.3 "less is more"):
#   - Alpine/musl base (ruby:<v>-alpine) — much smaller than debian-slim.
#   - Multi-stage: the build toolchain + -dev headers live ONLY in the throwaway
#     build stage, so they never reach the final image (that IS the "remove the
#     -dev packages after install").
#   - Runtime carries shared libs ONLY (vips, libpq) — no -dev, no compilers,
#     no postgresql-client (backup runs host-side via `pito backup`), no bash/zsh
#     (busybox sh is the shell; bin/docker-entrypoint is POSIX sh).
#   - The build-only Tailwind CLI (~114 MB) is stripped after assets:precompile.
#   - Gem docs/tests/examples stripped; bootsnap cache not shipped (rebuilt lazily).
#
# To build it locally instead:
#   docker build -t pito .
#   docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name pito pito
#
# Native development does NOT use this image — run bin/dev on the host (see README).

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.9
FROM docker.io/library/ruby:$RUBY_VERSION-alpine AS base

# Rails app lives here
WORKDIR /rails

# Runtime shared libraries ONLY — no -dev, no toolchain, no extra shells.
#   vips  → Active Storage image variants (avatars/thumbnails/covers)
#   libpq → the pg gem's runtime dependency
RUN apk add --no-cache vips libpq tzdata ca-certificates

# Production environment.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

# Throw-away build stage to reduce size of the final image.
FROM base AS build

# Build toolchain + headers. Lives only in this discarded stage, so none of it
# ships in the final image. ffi/nokogiri/pg ship musl precompiled gems, so in
# practice little compiles — these cover anything that does.
RUN apk add --no-cache build-base git pkgconf yaml-dev postgresql-dev

# Install application gems (production groups only), then prune build cruft:
# bundler cache, git checkouts, and each gem's top-level doc/ dir. NOTE: only the
# gem-ROOT doc/docs dirs are removed — never `test`/`spec` (some gems ship runtime
# code under those names, e.g. rack-test's lib/rack/test/), and never nested dirs.
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle config set --local no-document true && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/gems/*/doc "${BUNDLE_PATH}"/ruby/*/gems/*/docs

# Copy application code.
COPY . .

# Precompile assets WITHOUT a real master key. This is the only step that needs
# the Tailwind CLI — strip that ~114 MB build-only binary immediately after (keep
# lib/ so Bundler still loads tailwindcss-rails). Also drop any build-time tmp
# cache so it isn't shipped (bootsnap rebuilds its cache lazily at runtime).
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/gems/tailwindcss-ruby-*/exe && \
    rm -rf tmp/cache

# Final stage for the app image.
FROM base

# Non-root runtime user (Alpine busybox tools; /bin/sh shell — no bash).
# Create /var/lib/pito-assets owned by it BEFORE switching user: Docker seeds a
# fresh named volume with this dir's ownership, so Active Storage uploads can write
# (config/storage.yml → docker-compose.yml `rails_storage` volume). Without it the
# volume would be root-owned and the first upload would fail with EACCES.
RUN addgroup -g 1000 rails && \
    adduser -u 1000 -G rails -s /bin/sh -D rails && \
    mkdir -p /var/lib/pito-assets && chown 1000:1000 /var/lib/pito-assets

USER 1000:1000

# Copy built artifacts: gems, application.
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database (POSIX sh).
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default; overridable at runtime.
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
