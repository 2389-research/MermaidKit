using SkiaSharp;
using Xunit;

namespace MermaidKit.Tests;

/// The P/Invoke seam end-to-end: a Mermaid <b>source string</b> goes through
/// <see cref="MermaidNative"/> (P/Invoke → the Swift <c>mmk_*</c> C ABI in
/// <c>MermaidKitCShared.dll</c>) and comes back as a scene that draws to a Skia
/// canvas. This is the whole point of the native bridge — an app hands over
/// source, not a pre-lowered scene.
///
/// The native DLL is only present where it's been built (Windows CI). Elsewhere
/// (e.g. the headless Linux test run) these soft-skip — unless <c>MMK_NATIVE=1</c>
/// is set (the Windows CI job does), in which case a missing/broken DLL fails
/// rather than silently passing.
public class PInvokeTests
{
    private const string Source = "flowchart LR\n A[Start] --> B{Choice}\n B -->|yes| C((Done))";

    private static bool Require => Environment.GetEnvironmentVariable("MMK_NATIVE") == "1";

    /// Returns the version string, or null to signal "native absent, skip"
    /// (only when not required).
    private static string? TryNative()
    {
        try { return MermaidNative.Version(); }
        catch (DllNotFoundException) when (!Require) { return null; }
        catch (EntryPointNotFoundException) when (!Require) { return null; }
    }

    [Fact]
    public void VersionLoadsThroughPInvoke()
    {
        var v = TryNative();
        if (v is null) return; // native DLL absent (non-Windows) and not required
        Assert.Contains("MermaidKitC", v);
    }

    [Fact]
    public void SourceToSceneRendersThroughPInvoke()
    {
        if (TryNative() is null) return;

        var json = MermaidNative.SceneJson(Source);
        Assert.NotNull(json);
        Assert.Contains("\"type\":\"polyline\"", json);
        Assert.Contains("\"type\":\"shape\"", json);

        var scene = MermaidNative.Scene(Source);
        Assert.NotNull(scene);
        Assert.Contains(scene!.elements, e => e is ShapeElement);
        Assert.Contains(scene.elements, e => e is PolylineElement);

        int w = Math.Max(1, (int)Math.Ceiling(scene.size.w));
        int h = Math.Max(1, (int)Math.Ceiling(scene.size.h));
        using var bmp = new SKBitmap(w, h);
        using (var canvas = new SKCanvas(bmp))
            new SceneRenderer().Draw(scene, canvas);
        int inked = 0;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (bmp.GetPixel(x, y) != SKColors.White) inked++;
        Assert.True(inked > 300, $"native-parsed scene should render ink, got {inked}");
    }

    [Fact]
    public void NarrateThreadsThroughPInvoke()
    {
        if (TryNative() is null) return;
        var narration = MermaidNative.Narrate(Source);
        Assert.NotNull(narration);
        Assert.Contains("Start", narration!);
    }

    [Fact]
    public void InvalidSourceReturnsNull()
    {
        if (TryNative() is null) return;
        Assert.Null(MermaidNative.SceneJson("not a diagram at all"));
    }
}
