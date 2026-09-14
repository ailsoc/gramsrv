# syntax=docker/dockerfile:1.7

###############################################################################
# Images
###############################################################################

ARG GO_IMAGE=registry.access.redhat.com/ubi9/go-toolset:1.26
ARG RUNTIME_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal:latest

###############################################################################
# Builder Base
###############################################################################

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS build-base

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src

COPY go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY cmd/ ./cmd/
COPY deploy/ ./deploy/
COPY internal/ ./internal/

ENV CGO_ENABLED=0

###############################################################################
# Healthcheck
###############################################################################

FROM build-base AS build-healthcheck

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/telesrv-healthcheck \
      ./cmd/telesrv-healthcheck

###############################################################################
# Migration
###############################################################################

FROM build-base AS build-migrate

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/telesrv-migrate \
      ./cmd/telesrv-migrate

###############################################################################
# Build Functions
###############################################################################

FROM build-base AS build-core

ARG VCS_REF=unknown
ARG VCS_BRANCH=unknown
ARG VCS_TREE_STATE=unknown
ARG BUILD_DATE=unknown

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w \
        -X main.gitCommit=${VCS_REF} \
        -X main.gitBranch=${VCS_BRANCH} \
        -X main.gitTreeState=${VCS_TREE_STATE} \
        -X main.buildTime=${BUILD_DATE}" \
      -o /out/telesrv-core \
      ./cmd/telesrv-core

###############################################################################

FROM build-base AS build-edge

ARG VCS_REF=unknown
ARG VCS_BRANCH=unknown
ARG VCS_TREE_STATE=unknown
ARG BUILD_DATE=unknown

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w \
        -X main.gitCommit=${VCS_REF} \
        -X main.gitBranch=${VCS_BRANCH} \
        -X main.gitTreeState=${VCS_TREE_STATE} \
        -X main.buildTime=${BUILD_DATE}" \
      -o /out/telesrv-edge \
      ./cmd/telesrv-edge

###############################################################################

FROM build-base AS build-egress

ARG VCS_REF=unknown
ARG VCS_BRANCH=unknown
ARG VCS_TREE_STATE=unknown
ARG BUILD_DATE=unknown

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w \
        -X main.gitCommit=${VCS_REF} \
        -X main.gitBranch=${VCS_BRANCH} \
        -X main.gitTreeState=${VCS_TREE_STATE} \
        -X main.buildTime=${BUILD_DATE}" \
      -o /out/telesrv-egress \
      ./cmd/telesrv-egress

###############################################################################

FROM build-base AS build-file

ARG VCS_REF=unknown
ARG VCS_BRANCH=unknown
ARG VCS_TREE_STATE=unknown
ARG BUILD_DATE=unknown

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w \
        -X main.gitCommit=${VCS_REF} \
        -X main.gitBranch=${VCS_BRANCH} \
        -X main.gitTreeState=${VCS_TREE_STATE} \
        -X main.buildTime=${BUILD_DATE}" \
      -o /out/telesrv-file \
      ./cmd/telesrv-file

###############################################################################

FROM build-base AS build-sfu

ARG VCS_REF=unknown
ARG VCS_BRANCH=unknown
ARG VCS_TREE_STATE=unknown
ARG BUILD_DATE=unknown

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w \
        -X main.gitCommit=${VCS_REF} \
        -X main.gitBranch=${VCS_BRANCH} \
        -X main.gitTreeState=${VCS_TREE_STATE} \
        -X main.buildTime=${BUILD_DATE}" \
      -o /out/telesrv-sfu \
      ./cmd/telesrv-sfu

###############################################################################
# Admin UI
###############################################################################

FROM build-base AS build-admin

USER root

RUN dnf install -y nodejs npm \
 && dnf clean all

WORKDIR /src/cmd/telesrv-admin/web

RUN --mount=type=cache,target=/root/.npm \
    npm ci && npm run build

WORKDIR /src

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/tmp/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/telesrv-admin \
      ./cmd/telesrv-admin

###############################################################################
# Language Bundle
###############################################################################

FROM ${RUNTIME_IMAGE} AS langpack-bundle

WORKDIR /usr/share/telesrv/langpack

COPY data/langpack/ ./

RUN set -eux; \
    find . -type f -name '*.strings' | sort > /tmp/langpack-files; \
    test -s /tmp/langpack-files; \
    while read -r f; do sha256sum "$f"; done < /tmp/langpack-files \
      | sha256sum | cut -d ' ' -f1 \
      > .seed-fingerprint

###############################################################################
# Runtime Base
###############################################################################

FROM ${RUNTIME_IMAGE} AS runtime-base

ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="telesrv" \
      org.opencontainers.image.description="Telegram-like MTProto server" \
      org.opencontainers.image.source="https://github.com/iamxvbaba/gramsrv" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

RUN microdnf install -y \
        ca-certificates \
        tzdata \
    && microdnf clean all

ENV APP_ROOT=/opt/telesrv

RUN mkdir -p \
      ${APP_ROOT} \
      /etc/telesrv \
      /var/lib/telesrv \
      /usr/share/telesrv \
      /var/tmp/telesrv

RUN chgrp -R 0 \
        ${APP_ROOT} \
        /etc/telesrv \
        /var/lib/telesrv \
        /usr/share/telesrv \
        /var/tmp/telesrv \
 && chmod -R g=u \
        ${APP_ROOT} \
        /etc/telesrv \
        /var/lib/telesrv \
        /usr/share/telesrv \
        /var/tmp/telesrv

COPY --from=build-healthcheck \
  /out/telesrv-healthcheck \
  /usr/local/bin/

COPY deploy/docker/docker-entrypoint.sh \
  /usr/local/bin/telesrv-container-entrypoint

RUN chmod 0555 \
      /usr/local/bin/telesrv-healthcheck \
      /usr/local/bin/telesrv-container-entrypoint

WORKDIR ${APP_ROOT}

HEALTHCHECK --interval=30s --timeout=5s \
  --start-period=30s --retries=3 \
  CMD ["/usr/local/bin/telesrv-healthcheck"]

USER 1001

ENTRYPOINT ["/usr/local/bin/telesrv-container-entrypoint"]

###############################################################################
# CORE
###############################################################################

FROM runtime-base AS core

COPY --from=build-core \
     /out/telesrv-core \
     /usr/local/bin/

COPY --from=langpack-bundle \
     /usr/share/telesrv/langpack \
     /usr/share/telesrv/langpack

COPY deploy/docker/assets/seed-manifest.json \
     /usr/share/telesrv/seed-manifest.json

COPY deploy/docker/config/core.yaml \
     /etc/telesrv/core.yaml

EXPOSE 2400 2401 2420 2440

CMD ["telesrv-core","--config","/etc/telesrv/core.yaml"]

###############################################################################
# FILE
###############################################################################

FROM runtime-base AS file

COPY --from=build-file \
     /out/telesrv-file \
     /usr/local/bin/

COPY deploy/docker/config/file.yaml \
     /etc/telesrv/file.yaml

EXPOSE 2520

CMD ["telesrv-file","--config","/etc/telesrv/file.yaml"]

###############################################################################
# EGRESS
###############################################################################

FROM runtime-base AS egress

COPY --from=build-egress \
     /out/telesrv-egress \
     /usr/local/bin/

COPY deploy/docker/config/egress.yaml \
     /etc/telesrv/egress.yaml

EXPOSE 2510

CMD ["telesrv-egress","--config","/etc/telesrv/egress.yaml"]

###############################################################################
# SFU
###############################################################################

FROM runtime-base AS sfu

COPY --from=build-sfu \
     /out/telesrv-sfu \
     /usr/local/bin/

COPY deploy/docker/config/sfu.yaml \
     /etc/telesrv/sfu.yaml

EXPOSE 2450
EXPOSE 12399/udp
EXPOSE 12400/udp

CMD ["telesrv-sfu","--config","/etc/telesrv/sfu.yaml"]

###############################################################################
# ADMIN
###############################################################################

FROM runtime-base AS admin

COPY --from=build-admin \
     /out/telesrv-admin \
     /usr/local/bin/

COPY deploy/docker/config/admin.yaml \
     /etc/telesrv/admin.yaml

EXPOSE 2600

CMD ["telesrv-admin","--config","/etc/telesrv/admin.yaml"]

###############################################################################
# EDGE
###############################################################################

FROM runtime-base AS edge

USER 0

RUN microdnf install -y openssl \
 && microdnf clean all

RUN mkdir -p /var/lib/telesrv-edge \
 && chgrp -R 0 /var/lib/telesrv-edge \
 && chmod -R g=u /var/lib/telesrv-edge

COPY --from=build-edge \
     /out/telesrv-edge \
     /usr/local/bin/

COPY deploy/docker/config/edge.yaml \
     /etc/telesrv/edge.yaml

USER 1001

EXPOSE 2398

CMD ["telesrv-edge","--config","/etc/telesrv/edge.yaml"]

###############################################################################
# MIGRATION
###############################################################################

FROM runtime-base AS migrate

COPY --from=build-migrate \
     /out/telesrv-migrate \
     /usr/local/bin/

CMD ["telesrv-migrate"]

###############################################################################
# EDGE TEST
###############################################################################

FROM edge AS edge-test

USER 0

RUN mkdir -p /usr/share/telesrv/keys

COPY deploy/docker/assets/test-server-rsa.pub \
     /usr/share/telesrv/keys/test-server-rsa.pub

COPY deploy/docker/assets/test-server-rsa.pem.b64 \
     /usr/share/telesrv/keys/test-server-rsa.pem.b64

RUN chmod 0444 /usr/share/telesrv/keys/*

USER 1001
