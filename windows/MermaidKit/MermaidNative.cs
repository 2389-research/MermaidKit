using System.Runtime.InteropServices;

namespace MermaidKit;

/// The native bridge to the Swift core (the <c>mmk_*</c> C ABI) via P/Invoke —
/// the Windows analogue of Android's JNI seam. Calls into
/// <c>MermaidKitCShared.dll</c> (the Swift core built as a shared library),
/// which pulls in the Swift runtime DLLs alongside it.
///
/// This is what lets a .NET app go from a Mermaid <b>source string</b> to a
/// drawable scene with no Swift or native build of its own:
/// <see cref="Scene"/> parses the source natively and returns a
/// <see cref="SceneWire"/> ready for <see cref="SceneRenderer"/>.
///
/// Measurement note: this first slice passes no measure callback, so native
/// layout uses a coarse glyph-box metric. Threading a device-font measure
/// callback through P/Invoke (so layout measures with the face that draws) is a
/// later slice — see docs/notes/windows.md.
public static class MermaidNative
{
    private const string Library = "MermaidKitCShared";

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr mmk_scene_json(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string source,
        int prefersDark, IntPtr measure, IntPtr userdata);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr mmk_scene_json_options(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string source,
        IntPtr themeJson, int prefersDark, double textScale, IntPtr measure, IntPtr userdata);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr mmk_narrate(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string source);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern void mmk_free(IntPtr ptr);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr mmk_version();

    // The pre-2.5 (string, bool) entry points stay exactly as they were: C#
    // bakes optional arguments in at the call site, so assemblies compiled
    // against 2.4 reference these signatures. The text-scale variants are
    // separate overloads.

    /// The scene as wire JSON, or null when <paramref name="source"/> is empty or
    /// fails to parse.
    public static string? SceneJson(string source, bool prefersDark = false)
    {
        IntPtr ptr = mmk_scene_json(source, prefersDark ? 1 : 0, IntPtr.Zero, IntPtr.Zero);
        return TakeString(ptr);
    }

    /// The scene as wire JSON at <paramref name="textScale"/> — Dynamic Type for
    /// the diagram: text is laid out and drawn at that multiple of its size,
    /// clamped to 0.5–3 (a non-finite value is 1). The caller supplies it, e.g.
    /// from the system's text scale factor.
    public static string? SceneJson(string source, double textScale, bool prefersDark = false)
    {
        if (textScale == 1) return SceneJson(source, prefersDark);
        IntPtr ptr = mmk_scene_json_options(source, IntPtr.Zero, prefersDark ? 1 : 0, textScale,
                                            IntPtr.Zero, IntPtr.Zero);
        return TakeString(ptr);
    }

    private static string? TakeString(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(ptr); }
        finally { mmk_free(ptr); }
    }

    /// Parse <paramref name="source"/> natively into a <see cref="SceneWire"/>, or
    /// null when it fails to parse.
    public static SceneWire? Scene(string source, bool prefersDark = false)
    {
        var json = SceneJson(source, prefersDark);
        return json is null ? null : SceneWire.Parse(json);
    }

    /// <see cref="Scene(string, bool)"/> at <paramref name="textScale"/> (0.5–3).
    public static SceneWire? Scene(string source, double textScale, bool prefersDark = false)
    {
        var json = SceneJson(source, textScale, prefersDark);
        return json is null ? null : SceneWire.Parse(json);
    }

    /// An accessibility walkthrough of <paramref name="source"/> (for a control's
    /// AutomationProperties.Name), or null.
    public static string? Narrate(string source)
    {
        IntPtr ptr = mmk_narrate(source);
        if (ptr == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(ptr); }
        finally { mmk_free(ptr); }
    }

    /// The MermaidKitC ABI version string. The returned pointer is a static
    /// program-lifetime string owned by the library — it is NOT freed.
    public static string Version() => Marshal.PtrToStringUTF8(mmk_version()) ?? "";
}
