// JNI shim over the MermaidKitC C ABI (mmk_*). Built into libmermaidkit.so by
// `swift build` (the `MermaidJNI` package in this directory), which statically
// links MermaidKitC and lets the Swift runtime become NEEDED — so swift build
// handles all the Android linker/compiler-rt details. The .so, plus the Swift
// runtime .so closure, is packaged into the AAR's jniLibs/<abi>/. Kotlin's
// MermaidNative loads it.
//
// This layer keeps JNI in C — where JNIEnv is ergonomic — so the Swift side stays
// pure C ABI. It converts jstring<->UTF-8, calls the mmk_* functions, and honors
// their ownership contract (mmk_free every returned scene/narration string; never
// free the static version string).
//
// The mmk_* prototypes are declared inline (rather than #including mermaidkit.h)
// so this one C file needs no cross-package header path — it links the symbols
// from MermaidKitC, and their ABI is fixed. Keep in sync with
// Sources/MermaidKitC/include/mermaidkit.h.

#include <jni.h>

extern char *mmk_scene_json(const char *source, int prefers_dark,
                            void *measure, void *userdata);
extern char *mmk_narrate(const char *source);
extern void mmk_free(char *ptr);
extern const char *mmk_version(void);

// package ai.mermaidkit, class MermaidNative → Java_ai_mermaidkit_MermaidNative_*

JNIEXPORT jstring JNICALL
Java_ai_mermaidkit_MermaidNative_nativeSceneJson(JNIEnv *env, jclass clazz,
                                                 jstring source, jint prefersDark) {
    (void)clazz;
    if (source == NULL) return NULL;
    const char *src = (*env)->GetStringUTFChars(env, source, NULL);
    if (src == NULL) return NULL; // OOM already thrown by the VM

    // Null measure callback → the coarse glyph-box fallback in MermaidKitC.
    // (The device Paint.measureText callback is threaded in a later slice.)
    char *json = mmk_scene_json(src, prefersDark, NULL, NULL);
    (*env)->ReleaseStringUTFChars(env, source, src);

    if (json == NULL) return NULL; // nil/invalid source or parse failure
    jstring result = (*env)->NewStringUTF(env, json);
    mmk_free(json);
    return result;
}

JNIEXPORT jstring JNICALL
Java_ai_mermaidkit_MermaidNative_nativeNarrate(JNIEnv *env, jclass clazz, jstring source) {
    (void)clazz;
    if (source == NULL) return NULL;
    const char *src = (*env)->GetStringUTFChars(env, source, NULL);
    if (src == NULL) return NULL;

    char *narration = mmk_narrate(src);
    (*env)->ReleaseStringUTFChars(env, source, src);

    if (narration == NULL) return NULL;
    jstring result = (*env)->NewStringUTF(env, narration);
    mmk_free(narration);
    return result;
}

JNIEXPORT jstring JNICALL
Java_ai_mermaidkit_MermaidNative_nativeVersion(JNIEnv *env, jclass clazz) {
    (void)clazz;
    // mmk_version returns a static, program-lifetime string — do NOT free it.
    const char *version = mmk_version();
    return version ? (*env)->NewStringUTF(env, version) : NULL;
}
