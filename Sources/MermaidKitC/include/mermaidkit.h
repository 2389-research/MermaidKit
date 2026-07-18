/*
 * mermaidkit.h — the C ABI contract for MermaidKit's render pipeline.
 *
 * This header is the surface Android's JNI layer (or any C/C++ consumer) links
 * against. The functions are implemented in Swift (`@_cdecl`) in the
 * `MermaidKitC` target, which depends ONLY on the platform-free `MermaidLayout`
 * — no CoreGraphics/CoreText, no Silica/Cairo — so it cross-compiles for the
 * Android NDK and runs headless on macOS/Linux.
 *
 * Ownership: every non-NULL `char *` returned by `mmk_scene_json` and
 * `mmk_narrate` is a heap allocation the CALLER owns and MUST release with
 * `mmk_free`. `mmk_version` is the exception — it returns a pointer to a static
 * string the caller must NOT free. All functions return NULL on failure
 * (NULL/invalid source, parse failure) and never trap.
 */

#ifndef MERMAIDKIT_H
#define MERMAIDKIT_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The device-measure callback — the pinned measurement seam.
 *
 * Layout must measure text with the same face that will ultimately draw it, so
 * the JNI consumer passes a callback backed by the drawing `Paint`
 * (`Paint.measureText` on Android). It receives a UTF-8, NUL-terminated string
 * and a point size, and writes the measured width and height back through
 * `out_w` / `out_h`. `userdata` is the opaque pointer handed to
 * `mmk_scene_json`, round-tripped unchanged so the callback can reach its
 * Paint/context.
 *
 * A callback that writes nothing (leaves both outputs <= 0) is treated as
 * absent, and layout falls back to the coarse glyph-box approximation.
 */
typedef void (*MmkMeasure)(const char *text,
                           double font_size,
                           void *userdata,
                           double *out_w,
                           double *out_h);

/*
 * Parse a UTF-8 Mermaid `source`, lower it to a RenderScene, and return the
 * scene as deterministic (sorted-key) JSON.
 *
 * prefers_dark : non-zero selects the dark preset theme, zero the light one.
 * measure      : the device-measure callback, or NULL to use the built-in
 *                coarse approximation (headless / SVG).
 * userdata     : passed through verbatim to every `measure` invocation.
 *
 * Returns a malloc'd, NUL-terminated C string the caller owns (free via
 * `mmk_free`), or NULL when `source` is NULL or does not parse.
 */
char *mmk_scene_json(const char *source,
                     int prefers_dark,
                     MmkMeasure measure,
                     void *userdata);

/*
 * Narrate a UTF-8 Mermaid `source` as an accessibility walkthrough — feeds
 * Android's `contentDescription`.
 *
 * Returns a malloc'd, NUL-terminated C string the caller owns (free via
 * `mmk_free`), or NULL when `source` is NULL or does not parse.
 */
char *mmk_narrate(const char *source);

/*
 * Release a string returned by `mmk_scene_json` or `mmk_narrate`. Safe on NULL.
 * Do NOT pass the pointer returned by `mmk_version`.
 */
void mmk_free(char *ptr);

/*
 * The MermaidKitC ABI version string. Returns a pointer to a static string the
 * caller must NOT free.
 */
const char *mmk_version(void);

#ifdef __cplusplus
}
#endif

#endif /* MERMAIDKIT_H */
