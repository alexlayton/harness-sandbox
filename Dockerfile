# Dev sandbox image with Harness installed from GitHub releases.
# Debian (glibc) because the Harness Linux release binaries target gnu.
FROM docker.io/library/debian:trixie-slim

# Basic tools Harness's agent will want to use inside the sandbox.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git git-lfs openssh-client bash ripgrep less procps \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI (used when harness-sandbox is run with --github).
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Repos are mounted from the host (different owner); let git work in them.
RUN git config --system --add safe.directory '*'

# Pin the Harness release; override with --build-arg HARNESS_VERSION=vX.Y.Z
ARG HARNESS_VERSION=v0.10.0
ARG TARGETARCH

# Download, verify the SHA-256 checksum, and install to /usr/local/bin.
RUN set -eu; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      arm64) target=aarch64-unknown-linux-gnu ;; \
      amd64) target=x86_64-unknown-linux-gnu ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    pkg="harness-${HARNESS_VERSION}-${target}"; \
    url="https://github.com/alexlayton/harness/releases/download/${HARNESS_VERSION}"; \
    cd /tmp; \
    curl -fsSLO "${url}/${pkg}.tar.gz"; \
    curl -fsSLO "${url}/SHA256SUMS"; \
    grep " ${pkg}.tar.gz\$" SHA256SUMS | sha256sum -c -; \
    tar -xzf "${pkg}.tar.gz"; \
    install -m 0755 "${pkg}/harness" /usr/local/bin/harness; \
    rm -rf /tmp/*; \
    harness --version

# RTK (token-saving command rewriter used by Harness when `rtk = true`).
# rtk-oss is the Apache-2.0 edition (hooks + filters); set RTK_EDITION=rtk for the full one.
ARG RTK_VERSION=v1.1.0
ARG RTK_EDITION=rtk-oss
RUN set -eu; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      arm64) target=aarch64-unknown-linux-gnu ;; \
      amd64) target=x86_64-unknown-linux-musl ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    archive="${RTK_EDITION}-${target}.tar.gz"; \
    url="https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}"; \
    mkdir /tmp/rtk && cd /tmp/rtk; \
    curl -fsSLO "${url}/${archive}"; \
    curl -fsSLO "${url}/checksums.txt"; \
    grep " ${archive}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${archive}"; \
    install -m 0755 rtk /usr/local/bin/rtk; \
    rm -rf /tmp/rtk; \
    rtk --version

# Harness reads config + auth.json from here; we'll mount the host config dir onto it.
ENV HARNESS_CONFIG_DIR=/harness-config

# The project you want Harness to work on gets mounted here.
WORKDIR /workspace

CMD ["bash"]
