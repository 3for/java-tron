# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS remote-builder
ARG SOURCE_REPOSITORY="https://github.com/tronprotocol/java-tron.git"
ARG SOURCE_REF="master"

ENV NO_PROXY_CACHE="-o Acquire::BrokenProxy=true -o Acquire::http::No-Cache=true -o Acquire::http::Pipeline-Depth=0"
ENV TMP_DIR="/tron-build"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
ENV PATH="$PATH:$JAVA_HOME/bin"

RUN apt-get update $NO_PROXY_CACHE \
  && apt-get --quiet --yes install --no-install-recommends git 7zip curl ca-certificates openjdk-17-jdk-headless=17* \
  && apt-get clean \
  && rm -rf /var/cache/apt/archives/* /var/cache/apt/archives/partial/* \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "$SOURCE_REF" -- "$SOURCE_REPOSITORY" "$TMP_DIR/java-tron" \
  && cd "$TMP_DIR/java-tron" \
  && ./gradlew :framework:distZip -x test -x check --no-daemon \
  && cd framework/build/distributions \
  && 7z x -y java-tron-1.0.0.zip \
  && mv java-tron-1.0.0 /java-tron \
  && curl -4 -fsSLo /java-tron/config.conf https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/main_net_config.conf

# docker.sh creates this minimal context from a distribution built on the host.
FROM scratch AS local-distribution
COPY java-tron /java-tron

FROM ubuntu:24.04 AS runtime-base
ARG VERSION="dev"

ENV NO_PROXY_CACHE="-o Acquire::BrokenProxy=true -o Acquire::http::No-Cache=true -o Acquire::http::Pipeline-Depth=0"
ENV BASE_DIR="/java-tron"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
ENV PATH="$PATH:$JAVA_HOME/bin"
ENV LD_PRELOAD="/usr/lib/aarch64-linux-gnu/libtcmalloc_minimal.so.4"
ENV TCMALLOC_RELEASE_RATE=10

RUN apt-get update $NO_PROXY_CACHE \
  && apt-get --quiet --yes install --no-install-recommends ca-certificates libtcmalloc-minimal4 openjdk-17-jre-headless=17* \
  && apt-get clean \
  && rm -rf /var/cache/apt/archives/* /var/cache/apt/archives/partial/* \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 tron \
  && useradd --uid 10001 --gid 10001 --no-create-home --home-dir "$BASE_DIR" \
    --shell /usr/sbin/nologin tron \
  && mkdir -p "$BASE_DIR" \
  && chown 10001:10001 "$BASE_DIR"

WORKDIR $BASE_DIR

ENTRYPOINT ["./bin/FullNode"]

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="Java-TRON" \
      org.label-schema.description="TRON protocol" \
      org.label-schema.url="https://tron.network/" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/tronprotocol/java-tron.git" \
      org.label-schema.vendor="TRON protocol" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

FROM runtime-base AS local
COPY --chown=10001:10001 --from=local-distribution /java-tron /java-tron
USER 10001:10001

# Keep remote last so a plain BuildKit build retains the historical behavior.
FROM runtime-base AS remote
COPY --chown=10001:10001 --from=remote-builder /java-tron /java-tron
USER 10001:10001
