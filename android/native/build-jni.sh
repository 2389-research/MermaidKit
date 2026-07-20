#!/usr/bin/env bash
# Build the Android JNI native bundle for ONE ABI.
#
# Runs INSIDE the Swift Android toolchain image (swift + the installed Swift
# Android SDK), with the repo mounted at /work and an output dir at /out.
# Produces, in /out: libmermaidkit.so (the JNI shim with the Swift core linked
# in) and the transitive Swift-runtime .so closure — everything that goes into
# the AAR's jniLibs/<abi>/. See android/README.md.
#
#   docker run --rm -v "$REPO":/MermaidKit -v "$OUTDIR":/out swift-android-6.2 \
#     bash /MermaidKit/android/native/build-jni.sh x86_64
#
# The repo must be mounted at a path whose basename is "MermaidKit" — SwiftPM
# derives the `../..` path-dependency's package identity from the directory name.
set -euo pipefail
ABI="${1:-x86_64}"
case "$ABI" in
  arm64-v8a)   SWIFT_SDK=aarch64-unknown-linux-android24;   TRIPLE=aarch64-linux-android;;
  armeabi-v7a) SWIFT_SDK=armv7-unknown-linux-androideabi24; TRIPLE=arm-linux-androideabi;;
  x86_64)      SWIFT_SDK=x86_64-unknown-linux-android24;    TRIPLE=x86_64-linux-android;;
  *) echo "unknown ABI: $ABI (want arm64-v8a | armeabi-v7a | x86_64)"; exit 1;;
esac

BUNDLE=$(ls -d ~/.swiftpm/swift-sdks/*.artifactbundle | head -1)
SYSROOT=$(find "$BUNDLE" -type d -name "*sysroot*" | head -1)
RUNTIME_LIBDIR="$SYSROOT/usr/lib/$TRIPLE"

echo "== [$ABI] building libmermaidkit.so (release; JNI shim + MermaidKitC) =="
cd "$(cd "$(dirname "$0")" && pwd)"   # android/native, wherever it's mounted
swift build -c release --product mermaidkit --swift-sdk "$SWIFT_SDK" --build-path "/tmp/ab-$ABI" >/dev/null
JNI_SO=$(find "/tmp/ab-$ABI" -name libmermaidkit.so | head -1)
[ -n "$JNI_SO" ] || { echo "libmermaidkit.so not produced"; exit 1; }
cp "$JNI_SO" /out/

echo "== [$ABI] gathering the Swift-runtime .so closure =="
# Android provides these — never bundle them (doing so can break the loader).
DENY="libc.so libm.so libdl.so liblog.so libandroid.so libGLESv2.so libGLESv3.so libEGL.so libOpenSLES.so libvulkan.so libjnigraphics.so libmediandk.so libz.so"
declare -A seen
copy_closure() {
  local so="$1" dep
  for dep in $(readelf -d "$so" 2>/dev/null | awk -F'[][]' '/NEEDED/{print $2}'); do
    case " $DENY " in *" $dep "*) continue;; esac
    [ -n "${seen[$dep]:-}" ] && continue
    if [ -f "$RUNTIME_LIBDIR/$dep" ]; then
      seen[$dep]=1
      cp "$RUNTIME_LIBDIR/$dep" /out/
      copy_closure "$RUNTIME_LIBDIR/$dep"
    fi
  done
}
copy_closure /out/libmermaidkit.so

# Strip each .so with llvm-objcopy (== llvm-strip) — removes .symtab/debug while
# keeping the exported .dynsym (the Java_* entry points + NEEDED deps the loader
# and JNI resolve). AGP does NOT strip PREBUILT jniLibs (only libs it builds via
# CMake/ndk-build), so this is the authoritative strip. llvm-objcopy handles every
# Android ELF, including the x86_64 one host GNU strip can't parse.
STRIP=$(command -v llvm-objcopy || command -v llvm-strip)
before=$(du -sb /out | cut -f1)
for so in /out/*.so; do "$STRIP" --strip-unneeded "$so"; done
after=$(du -sb /out | cut -f1)

echo "== [$ABI] jniLibs bundle (stripped) =="
ls -1 /out | sort
echo "total: $(ls -1 /out | wc -l) .so, $((after/1024/1024))M (was $((before/1024/1024))M unstripped)"
