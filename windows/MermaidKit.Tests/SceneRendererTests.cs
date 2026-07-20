using System.Text.Json;
using SkiaSharp;
using Xunit;

namespace MermaidKit.Tests;

/// Proves the .NET half: the exact JSON the native core emits (captured as golden
/// fixtures) deserializes with the discriminated converters, and renders real ink
/// on a SkiaSharp canvas — the same Skia engine Android draws with.
public class SceneRendererTests
{
    private static string LoadFixture(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", name + ".json"));

    [Fact]
    public void ParsesFlowchartWithDiscriminatedTypes()
    {
        var scene = SceneWire.Parse(LoadFixture("flowchart"));
        Assert.Equal(1, scene.version);
        Assert.NotEmpty(scene.elements);

        // The `type` discriminator (not first in sorted-key JSON) lands each
        // element on the right record via the custom converters.
        Assert.Contains(scene.elements, e => e is PolylineElement);
        Assert.Contains(scene.elements, e => e is ShapeElement);
        Assert.Contains(scene.elements, e => e is TextElement);

        // Nested discriminated geometry: a rounded rect (rect node), a polygon
        // (diamond), and an ellipse (circle).
        var paths = scene.elements.OfType<ShapeElement>().Select(s => s.path).ToList();
        Assert.Contains(paths, p => p is RoundedRect);
        Assert.Contains(paths, p => p is Polygon);
        Assert.Contains(paths, p => p is Ellipse);

        var edge = scene.elements.OfType<PolylineElement>().First();
        Assert.True(edge.points.Count >= 2);
        Assert.True(edge.endArrow);
    }

    [Fact]
    public void RendersNonBlankBitmap()
    {
        var scene = SceneWire.Parse(LoadFixture("flowchart"));
        int w = Math.Max(1, (int)Math.Ceiling(scene.size.w));
        int h = Math.Max(1, (int)Math.Ceiling(scene.size.h));
        using var bmp = new SKBitmap(w, h);
        using (var canvas = new SKCanvas(bmp))
            new SceneRenderer().Draw(scene, canvas);

        int inked = 0;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (bmp.GetPixel(x, y) != SKColors.White) inked++;
        // Shapes + strokes + arrowheads land ink regardless of font availability.
        Assert.True(inked > 300, $"expected ink on the canvas, got {inked}");
    }

    [Fact]
    public void ParseColorReordersToArgb()
    {
        var c = SceneRenderer.ParseColor("#1D1D1F59");
        Assert.Equal(0x1D, c.Red);
        Assert.Equal(0x1D, c.Green);
        Assert.Equal(0x1F, c.Blue);
        Assert.Equal(0x59, c.Alpha);
        // 6-digit form is fully opaque.
        Assert.Equal(255, SceneRenderer.ParseColor("#5B8FF9").Alpha);
    }

    [Fact]
    public void ParsesSequenceDiagram()
    {
        var scene = SceneWire.Parse(LoadFixture("sequence"));
        Assert.NotEmpty(scene.elements);
        Assert.Contains(scene.elements, e => e is TextElement);
    }

    [Fact]
    public void UnknownElementTypeThrows()
    {
        const string bad = """
            {"version":1,"size":{"w":1,"h":1},"background":"#FFFFFFFF","elements":[{"type":"blob"}]}
            """;
        Assert.Throws<JsonException>(() => SceneWire.Parse(bad));
    }

    [Fact]
    public void ToleratesUnknownFields()
    {
        // A newer producer adds a field the reader doesn't know — must not throw.
        const string forward = """
            {"version":2,"size":{"w":1,"h":1},"background":"#FFFFFFFF","futureField":true,"elements":[]}
            """;
        var scene = SceneWire.Parse(forward);
        Assert.Equal(2, scene.version);
    }
}
