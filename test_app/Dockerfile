# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t test_app .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name test_app test_app

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
# SECURITY: Exclude test dependencies to reduce attack surface
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS="4" \
    BUNDLE_RETRY="3"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# SECURITY: Add security-related packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y dumb-init && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build --chown=rails:rails "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=rails:rails /rails /rails

# Run and own only the runtime files as a non-root user for security
# SECURITY: Create user with minimal privileges and ensure directories exist
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash --no-log-init && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp && \
    chmod 750 db log storage tmp && \
    chmod 700 /home/rails && \
    # SECURITY: Prevent privilege escalation
    echo "rails ALL=(ALL) NOPASSWD: /bin/false" > /etc/sudoers.d/rails && \
    chmod 440 /etc/sudoers.d/rails && \
    # SECURITY: Remove unnecessary setuid/setgid binaries
    find / -perm /4000 -type f -exec chmod u-s {} \; 2>/dev/null || true && \
    find / -perm /2000 -type f -exec chmod g-s {} \; 2>/dev/null || true && \
    # SECURITY: Remove shells except bash (needed for entrypoint)
    rm -f /bin/sh /usr/bin/sh /bin/dash /usr/bin/dash 2>/dev/null || true

# SECURITY: Drop all capabilities and run as non-root
USER 1000:1000

# SECURITY: Use dumb-init to handle signals properly and prevent zombie processes
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/rails/bin/docker-entrypoint"]

# SECURITY: Run on unprivileged port (Rails default 3000) instead of 80
EXPOSE 3000

# SECURITY: Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1

# Start server via Thruster by default, this can be overwritten at runtime
CMD ["./bin/thrust", "./bin/rails", "server"]
