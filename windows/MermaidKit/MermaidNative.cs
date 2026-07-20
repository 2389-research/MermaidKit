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
    private static extern IntPtr mmk_narrate(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string source);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern void mmk_free(IntPtr ptr);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr mmk_version();

    /// The scene as wire JSON, or null when <paramref name="source"/> is empty or
    /// fails to parse.
    public static string? SceneJson(string source, bool prefersDark = false)
    {
        IntPtr ptr = mmk_scene_json(source, prefersDark ? 1 : 0, IntPtr.Zero, IntPtr.Zero);
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
