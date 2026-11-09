#!/bin/sh
# Runs the Go toolchain in Docker, so that no Go needs to be installed for development:
#
#   apps/cli/dev.sh go test ./...
#   GOOS=darwin GOARCH=arm64 apps/cli/dev.sh build     # writes apps/cli/dist/novos
#
# CI uses its own Go; this is only for the Mac.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CORE=$(CDPATH= cd -- "$HERE/../.." && pwd)
run() {
    docker run --rm -v "$CORE":/src -v novos-gomod:/go/pkg/mod -v novos-gobuild:/root/.cache/go-build \
        -w /src/apps/cli -e GOOS -e GOARCH -e VERSION -e CGO_ENABLED=0 golang:1.23 "$@"
}
if [ "${1:-}" = build ]; then
    run sh -c 'env -u GOOS -u GOARCH go generate ./... && go build -trimpath -ldflags "-s -w -X main.version=${VERSION:-dev}" -o dist/novos .'
else
    run "$@"
fi
