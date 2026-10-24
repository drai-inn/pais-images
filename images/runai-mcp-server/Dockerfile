# runai-mcp-server: NVIDIA Run:ai's MCP server (tools for agents over Run:ai's API), built from the open-source
# dsx-ai-factory/run-ai repo at the release tag in VERSION. That tag matches the Run:ai control plane it serves
# (ai-gpu-test runs 3.0.20). NVIDIA publishes no image of the open-source server: NGC's
# nvcr.io/nvidia/runai/runai-mcp-server is the commercial 2.x line, with a different tool set.
#
# The build stage fetches only runai-mcp-server/ and the in-repo modules its go.mod `replace`s point to, then builds
# with the module's own go.sum. The final stage is upstream's runai-mcp-server/Dockerfile: scratch, CA certificates,
# a writable /tmp, user 65532, `runai-mcp-server serve`.

ARG GO_VERSION=1.27.1

FROM golang:${GO_VERSION} AS build
ARG RUNAI_VERSION
ARG TARGETARCH
RUN test -n "${RUNAI_VERSION}" || { echo "RUNAI_VERSION build arg is required" >&2; exit 1; }
WORKDIR /src
RUN git clone --quiet --depth 1 --branch "${RUNAI_VERSION}" --filter=blob:none --sparse \
        https://github.com/dsx-ai-factory/run-ai.git . \
    && git sparse-checkout set runai-mcp-server \
    && git sparse-checkout add $(sed -n 's#^replace .* => \.\./\(.*\)$#\1#p' runai-mcp-server/go.mod)
WORKDIR /src/runai-mcp-server
RUN CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" go build -trimpath \
        -ldflags "-s -w -X github.com/dsx-ai-factory/run-ai/runai-mcp-server/internal/server.serverVersion=${RUNAI_VERSION}" \
        -o /out/runai-mcp-server ./cmd/runai-mcp

FROM registry.access.redhat.com/ubi9/ubi-minimal AS base
# /tmp is copied as a child of /temp so its mode survives COPY (as upstream does).
RUN mkdir -p /temp/tmp && chown 65532:0 /temp/tmp && chmod 770 /temp/tmp

FROM scratch
ARG RUNAI_VERSION
LABEL org.opencontainers.image.title="runai-mcp-server" \
      org.opencontainers.image.version="${RUNAI_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="NVIDIA Run:ai MCP server, built from dsx-ai-factory/run-ai tag ${RUNAI_VERSION}"
COPY --from=base /etc/passwd /etc/passwd
COPY --from=base /etc/group /etc/group
COPY --from=base /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=base /etc/pki/ /etc/pki/
COPY --from=base /temp /
WORKDIR /
COPY --from=build /src/runai-mcp-server/NOTICE /NOTICE
COPY --from=build /out/runai-mcp-server /runai-mcp-server
USER 65532:65532
ENTRYPOINT ["./runai-mcp-server"]
CMD ["serve"]
