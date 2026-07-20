#!/usr/bin/env bash
# Android buildability gate (Phase 1).
#
# Cross-compiles the platform-free core — MermaidLayout + the MermaidKitC C ABI —
# to Android (aarch64) using the Swift Android SDK inside Docker. This catches
# Bionic/Android libc gaps that the macOS and Linux/glibc builds cannot: e.g.
# `read`/`ioctl`/`strdup`/`isatty` needing the Android libc module, which
# `#if canImport(Glibc)` misses on Android. The C ABI (`mmk_scene_json` etc.) is
# what the JNI layer / Android AAR will link, so this proves it actually builds
# for the device before any NDK/Gradle work.
#
# Requires Docker. The toolchain image and the Android SDK bundle are pinned to
# matching Swift versions — the SDK's .swiftmodule is not ABI-stable across
# patch releases, so the image MUST be 6.2.0 to match the 6.2-RELEASE bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="swift:6.2.0"
BUNDLE="https://github.com/finagolfin/swift-android-sdk/releases/download/6.2/swift-6.2-RELEASE-android-24-0.1.artifactbundle.tar.gz"
CHECKSUM="c26ebfd4e32c0ca1beabcc45729b62042da57ee76d7d043f63f2235da90dc491"
SDK="aarch64-unknown-linux-android24"

echo "Cross-compiling MermaidKitC → $SDK (Swift Android SDK in $IMAGE)…"
docker run --rm -v "$PWD":/repo:ro "$IMAGE" bash -c "
  set -e
  swift sdk install '$BUNDLE' --checksum '$CHECKSUM' >/dev/null 2>&1
  mkdir /work && cp -r /repo/Package.swift /repo/Sources /repo/Tests /work/ && cd /work
  swift build --target MermaidKitC --swift-sdk '$SDK' --build-path /tmp/abuild
"
echo "✓ MermaidLayout + MermaidKitC cross-compile cleanly to Android ($SDK)"
