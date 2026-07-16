#!/usr/bin/env bash
# Build + test the whole package on Linux — including the Silica (Cairo/
# FontConfig) render backend — exactly the way the `linux` CI job does, in a
# swift:6.2 container. This is how to reproduce/iterate on Linux-only failures
# (or verify a render change) without pushing. Requires Docker.
#
# The Silica backend is behind the `LinuxRaster` package trait (default OFF, so
# Apple consumers stay Silica-free — see Package.swift), so the build/test here
# opt in with `--traits LinuxRaster`. The plain-`swift build` of MermaidLayout
# mirrors CI's check that the platform-free core still builds Silica-free.
#
# A named volume caches the build across runs; the Cairo/FontConfig system
# packages install on each run (~30s) so the container stays stock. See
# docs/notes/linux-rendering-via-silica.md for how the backend works.
set -euo pipefail
cd "$(dirname "$0")/.."

docker run --rm \
  -v "$PWD":/pkg \
  -v mermaidkit-linux-build:/pkg/.build \
  -w /pkg swift:6.2 bash -euc '
    # Use HTTPS apt mirrors: harmless normally, and the only ones reachable from
    # networks that allow 443 but not 80 (e.g. some CI/sandbox egress rules).
    find /etc/apt -name "*.sources" -o -name "*.list" | xargs -r sed -i "s|http://|https://|g"
    apt-get update -qq
    apt-get install -y --no-install-recommends -qq \
      libcairo2-dev libfontconfig1-dev pkg-config fonts-dejavu-core fontconfig >/dev/null
    fc-cache -f >/dev/null
    swift --version
    swift build --traits LinuxRaster
    swift test --traits LinuxRaster
    # The platform-free core must ALSO build with the default (Silica-free)
    # graph — the configuration a headless from:-pinned consumer resolves.
    swift build --target MermaidLayout
  '
