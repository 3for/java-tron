FROM ubuntu:24.04 AS builder
ARG SOURCE_MODE="remote"
ARG SOURCE_REPOSITORY="https://github.com/tronprotocol/java-tron.git"
ARG SOURCE_REF="master"

ENV NO_PROXY_CACHE="-o Acquire::BrokenProxy=true -o Acquire::http::No-Cache=true -o Acquire::http::Pipeline-Depth=0"
ENV TMP_DIR="/tron-build"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
ENV PATH="$PATH:$JAVA_HOME/bin"

# Install the build toolchain before copying source so local code changes do
# not invalidate the JDK and package layers.
RUN apt-get update $NO_PROXY_CACHE \
  && apt-get --quiet --yes install --no-install-recommends git 7zip curl ca-certificates openjdk-17-jdk-headless=17* \
  && apt-get clean \
  && rm -rf /var/cache/apt/archives/* /var/cache/apt/archives/partial/* \
  && rm -rf /var/lib/apt/lists/*

# The local source mode reads the repository from the build context. The
# default remote mode retains the historical behavior of building master.
COPY . /tron-build/build-context

RUN if [ "$SOURCE_MODE" = "local" ]; then \
      test -x "$TMP_DIR/build-context/gradlew" \
      || { echo "Local build context is not a java-tron checkout." >&2; exit 1; }; \
      mkdir -p "$TMP_DIR/java-tron"; \
      cp -a "$TMP_DIR/build-context/." "$TMP_DIR/java-tron/"; \
    elif [ "$SOURCE_MODE" = "remote" ]; then \
      git clone --depth 1 --branch "$SOURCE_REF" -- "$SOURCE_REPOSITORY" "$TMP_DIR/java-tron"; \
    else \
      echo "Unsupported SOURCE_MODE: $SOURCE_MODE; expected local or remote." >&2; \
      exit 1; \
    fi \
  && cd "$TMP_DIR/java-tron" \
  && ./gradlew :framework:distZip -x test -x check --no-daemon \
  && cd framework/build/distributions \
  && 7z x -y java-tron-1.0.0.zip \
  && mv java-tron-1.0.0 /java-tron \
  && curl -4 -fsSLo /java-tron/config.conf https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/main_net_config.conf

FROM ubuntu:24.04 AS runtime
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

COPY --from=builder /java-tron /java-tron

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
