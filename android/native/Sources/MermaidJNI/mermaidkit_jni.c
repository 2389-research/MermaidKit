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

// Mirrors MmkMeasure in Sources/MermaidKitC/include/mermaidkit.h.
typedef void (*MmkMeasure)(const char *text, double font_size, void *userdata,
                           double *out_w, double *out_h);

extern char *mmk_scene_json(const char *source, int prefers_dark,
                            MmkMeasure measure, void *userdata);
extern char *mmk_scene_json_themed(const char *source, const char *theme_json,
                                   MmkMeasure measure, void *userdata);
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
    // (nativeSceneJsonMeasured threads the device Paint.measureText through.)
    char *json = mmk_scene_json(src, prefersDark, NULL, NULL);
    (*env)->ReleaseStringUTFChars(env, source, src);

    if (json == NULL) return NULL; // nil/invalid source or parse failure
    jstring result = (*env)->NewStringUTF(env, json);
    mmk_free(json);
    return result;
}

// The device-measure seam. `userdata` carries the JVM handles a trampoline needs
// to call back into a Kotlin `MermaidNative.Measurer`. mmk_scene_json invokes the
// callback synchronously on THIS (the JNI) thread, so `env` stays valid — no
// AttachCurrentThread, no cross-thread ref juggling.
typedef struct {
    JNIEnv *env;
    jobject measurer;   // MermaidNative.Measurer
    jmethodID measure;  // double[] measure(String text, double fontSize)
} MeasureCtx;

// The C function pointer handed to mmk_scene_json. Bridges one measure request
// into the Kotlin callback and writes the width/height back through the ABI's
// out-pointers. On any failure it leaves the outputs untouched (<= 0), which the
// ABI treats as "absent" and falls back to its coarse metric for that run.
static void measure_trampoline(const char *text, double font_size, void *userdata,
                               double *out_w, double *out_h) {
    MeasureCtx *ctx = (MeasureCtx *)userdata;
    JNIEnv *env = ctx->env;

    jstring jtext = (*env)->NewStringUTF(env, text ? text : "");
    if (jtext == NULL) { (*env)->ExceptionClear(env); return; }

    jdoubleArray result =
        (jdoubleArray)(*env)->CallObjectMethod(env, ctx->measurer, ctx->measure, jtext, font_size);
    (*env)->DeleteLocalRef(env, jtext);

    // A throwing measurer must not abort layout — clear and fall back.
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        if (result != NULL) (*env)->DeleteLocalRef(env, result);
        return;
    }
    if (result == NULL) return;

    if ((*env)->GetArrayLength(env, result) >= 2) {
        jdouble wh[2];
        (*env)->GetDoubleArrayRegion(env, result, 0, 2, wh);
        if (out_w) *out_w = wh[0];
        if (out_h) *out_h = wh[1];
    }
    (*env)->DeleteLocalRef(env, result);
}

JNIEXPORT jstring JNICALL
Java_ai_mermaidkit_MermaidNative_nativeSceneJsonMeasured(JNIEnv *env, jclass clazz,
                                                         jstring source, jint prefersDark,
                                                         jobject measurer) {
    (void)clazz;
    if (source == NULL || measurer == NULL) return NULL;

    jclass mcls = (*env)->GetObjectClass(env, measurer);
    jmethodID mid = (*env)->GetMethodID(env, mcls, "measure", "(Ljava/lang/String;D)[D");
    (*env)->DeleteLocalRef(env, mcls);
    if (mid == NULL) { (*env)->ExceptionClear(env); return NULL; } // no such method

    const char *src = (*env)->GetStringUTFChars(env, source, NULL);
    if (src == NULL) return NULL;

    MeasureCtx ctx = { env, measurer, mid };
    char *json = mmk_scene_json(src, prefersDark, measure_trampoline, &ctx);
    (*env)->ReleaseStringUTFChars(env, source, src);

    if (json == NULL) return NULL;
    jstring result = (*env)->NewStringUTF(env, json);
    mmk_free(json);
    return result;
}

// Themed + measured: `themeJson` is a ThemeWire JSON string (or NULL for the
// light preset), `measurer` may be NULL (coarse metric).
JNIEXPORT jstring JNICALL
Java_ai_mermaidkit_MermaidNative_nativeSceneJsonThemed(JNIEnv *env, jclass clazz,
                                                       jstring source, jstring themeJson,
                                                       jobject measurer) {
    (void)clazz;
    if (source == NULL) return NULL;

    const char *src = (*env)->GetStringUTFChars(env, source, NULL);
    if (src == NULL) return NULL;

    const char *theme = NULL;
    if (themeJson != NULL) {
        theme = (*env)->GetStringUTFChars(env, themeJson, NULL);
        if (theme == NULL) { (*env)->ReleaseStringUTFChars(env, source, src); return NULL; }
    }

    // Resolve the optional measure callback exactly as nativeSceneJsonMeasured.
    MeasureCtx ctx;
    MmkMeasure cb = NULL;
    if (measurer != NULL) {
        jclass mcls = (*env)->GetObjectClass(env, measurer);
        jmethodID mid = (*env)->GetMethodID(env, mcls, "measure", "(Ljava/lang/String;D)[D");
        (*env)->DeleteLocalRef(env, mcls);
        if (mid != NULL) {
            ctx.env = env; ctx.measurer = measurer; ctx.measure = mid;
            cb = measure_trampoline;
        } else {
            (*env)->ExceptionClear(env); // no measure() → fall back to coarse metric
        }
    }

    char *json = mmk_scene_json_themed(src, theme, cb, cb ? &ctx : NULL);
    (*env)->ReleaseStringUTFChars(env, source, src);
    if (theme != NULL) (*env)->ReleaseStringUTFChars(env, themeJson, theme);

    if (json == NULL) return NULL;
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
