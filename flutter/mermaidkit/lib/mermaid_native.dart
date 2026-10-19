// The native bridge to the Swift core (the `mmk_*` C ABI) via `dart:ffi` — the
// Flutter analogue of Android's JNI and .NET's P/Invoke. `dart:ffi` calls the
// `@_cdecl` C functions in the Swift core (built as a shared library) directly.
//
// This lets a Flutter app go from a Mermaid **source string** to a drawable
// scene with no Swift toolchain of its own: [scene] parses natively and returns
// a [SceneWire] ready for [MermaidPainter].
//
// The library is `MermaidKitCShared` (`.so`/`.dylib`/`.dll`). Override the load
// path with the `MMK_LIB` environment variable (used by the FFI test to point at
// a freshly-built library); otherwise it's looked up by platform name on the
// loader path (an app bundles it next to its binary).

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'scene_wire.dart';

typedef _SceneJsonNative = Pointer<Utf8> Function(
    Pointer<Utf8> source, Int32 prefersDark, Pointer<Void> measure, Pointer<Void> userdata);
typedef _SceneJsonDart = Pointer<Utf8> Function(
    Pointer<Utf8> source, int prefersDark, Pointer<Void> measure, Pointer<Void> userdata);
typedef _SceneJsonOptionsNative = Pointer<Utf8> Function(Pointer<Utf8> source, Pointer<Utf8> themeJson,
    Int32 prefersDark, Double textScale, Pointer<Void> measure, Pointer<Void> userdata);
typedef _SceneJsonOptionsDart = Pointer<Utf8> Function(Pointer<Utf8> source, Pointer<Utf8> themeJson,
    int prefersDark, double textScale, Pointer<Void> measure, Pointer<Void> userdata);
typedef _NarrateNative = Pointer<Utf8> Function(Pointer<Utf8> source);
typedef _NarrateDart = Pointer<Utf8> Function(Pointer<Utf8> source);
typedef _FreeNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeDart = void Function(Pointer<Utf8> ptr);
typedef _VersionNative = Pointer<Utf8> Function();

class MermaidNative {
  static final DynamicLibrary _lib = _openLibrary();

  static DynamicLibrary _openLibrary() {
    final override = Platform.environment['MMK_LIB'];
    if (override != null) return DynamicLibrary.open(override);
    final name = Platform.isWindows
        ? 'MermaidKitCShared.dll'
        : Platform.isMacOS
            ? 'libMermaidKitCShared.dylib'
            : 'libMermaidKitCShared.so';
    return DynamicLibrary.open(name);
  }

  static final _sceneJson =
      _lib.lookupFunction<_SceneJsonNative, _SceneJsonDart>('mmk_scene_json');
  static final _sceneJsonOptions = _lib
      .lookupFunction<_SceneJsonOptionsNative, _SceneJsonOptionsDart>('mmk_scene_json_options');
  static final _narrate =
      _lib.lookupFunction<_NarrateNative, _NarrateDart>('mmk_narrate');
  static final _free = _lib.lookupFunction<_FreeNative, _FreeDart>('mmk_free');
  static final _version =
      _lib.lookupFunction<_VersionNative, Pointer<Utf8> Function()>('mmk_version');

  /// The scene as wire JSON, or null when `source` is empty or fails to parse.
  ///
  /// [textScale] is Dynamic Type for the diagram — pass
  /// `MediaQuery.textScalerOf(context).scale(1)` to follow the user's text
  /// size. Text is laid out and drawn at that multiple of its size (clamped to
  /// 0.5–3); 1 is the default size.
  static String? sceneJson(String source, {bool prefersDark = false, double textScale = 1}) {
    final src = source.toNativeUtf8();
    try {
      final ptr = textScale == 1
          ? _sceneJson(src, prefersDark ? 1 : 0, nullptr, nullptr)
          : _sceneJsonOptions(src, nullptr, prefersDark ? 1 : 0, textScale, nullptr, nullptr);
      if (ptr == nullptr) return null;
      try {
        return ptr.toDartString();
      } finally {
        _free(ptr);
      }
    } finally {
      malloc.free(src);
    }
  }

  /// Parse `source` natively into a [SceneWire], or null when it fails to parse.
  static SceneWire? scene(String source, {bool prefersDark = false, double textScale = 1}) {
    final json = sceneJson(source, prefersDark: prefersDark, textScale: textScale);
    return json == null ? null : SceneWire.parse(json);
  }

  /// An accessibility walkthrough of `source` (for a `Semantics` label), or null.
  static String? narrate(String source) {
    final src = source.toNativeUtf8();
    try {
      final ptr = _narrate(src);
      if (ptr == nullptr) return null;
      try {
        return ptr.toDartString();
      } finally {
        _free(ptr);
      }
    } finally {
      malloc.free(src);
    }
  }

  /// The MermaidKitC ABI version string (its pointer is static — never freed).
  static String version() => _version().toDartString();
}
