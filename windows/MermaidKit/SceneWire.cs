using System.Text.Json;
using System.Text.Json.Serialization;

namespace MermaidKit;

// The .NET twin of Swift's `SceneWire` — the explicit, language-neutral wire
// schema the native core emits (`mmk_scene_json`). Coordinates are points in a
// top-left-origin space; colors are `#RRGGBBAA` strings (parse when drawing).
//
// The wire tags each element/shape/verb with a `type` discriminator, but the
// bytes are sorted-key JSON so `type` is NOT the first property — System.Text.Json's
// built-in polymorphism needs it first, so each hierarchy gets a small custom
// converter that reads `type` at any position (the .NET analogue of Kotlin's
// @JsonClassDiscriminator and Swift's hand-written Codable).

public sealed record Point(double x, double y);
public sealed record Size(double w, double h);
public sealed record Rect(double x, double y, double w, double h);
public sealed record Stroke(string color, double width, bool dashed = false);

[JsonConverter(typeof(ShapePathConverter))]
public abstract record ShapePath;
public sealed record RoundedRect(Rect rect, double radius) : ShapePath;
public sealed record Ellipse(Rect rect) : ShapePath;
public sealed record Polygon(IReadOnlyList<Point> points) : ShapePath;
public sealed record PathShape(IReadOnlyList<PathVerb> verbs) : ShapePath;

[JsonConverter(typeof(PathVerbConverter))]
public abstract record PathVerb;
public sealed record MoveVerb(Point point) : PathVerb;
public sealed record LineVerb(Point point) : PathVerb;
public sealed record QuadVerb(Point to, Point control) : PathVerb;
public sealed record CloseVerb : PathVerb;

[JsonConverter(typeof(ElementConverter))]
public abstract record Element;
public sealed record ShapeElement(ShapePath path, string? fill, Stroke? stroke) : Element;
public sealed record PolylineElement(
    IReadOnlyList<Point> points, Stroke stroke, bool startArrow, bool endArrow) : Element;
public sealed record TextElement(
    string @string, Point center, double fontSize, string weight,
    string color, string? backing, double rotation) : Element;

public sealed record SceneWire(int version, Size size, string background, IReadOnlyList<Element> elements)
{
    public const int SupportedVersion = 1;

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = false,
    };

    /// Parse wire JSON (e.g. the string from `mmk_scene_json`) into a scene.
    public static SceneWire Parse(string json) =>
        JsonSerializer.Deserialize<SceneWire>(json, Options)
            ?? throw new JsonException("scene JSON deserialized to null");
}

// MARK: - Discriminated converters (read `type` at any position)

file static class JsonReadHelpers
{
    internal static string TypeOf(JsonElement obj) =>
        obj.TryGetProperty("type", out var t)
            ? t.GetString() ?? throw new JsonException("null type discriminator")
            : throw new JsonException("missing type discriminator");

    internal static T Req<T>(JsonElement obj, string name, JsonSerializerOptions o) =>
        obj.TryGetProperty(name, out var v)
            ? v.Deserialize<T>(o) ?? throw new JsonException($"null required field '{name}'")
            : throw new JsonException($"missing required field '{name}'");

    internal static T? Opt<T>(JsonElement obj, string name, JsonSerializerOptions o) where T : class =>
        obj.TryGetProperty(name, out var v) && v.ValueKind != JsonValueKind.Null
            ? v.Deserialize<T>(o) : null;

    internal static bool Flag(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    internal static double Num(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) ? v.GetDouble()
            : throw new JsonException($"missing number '{name}'");

    internal static string Str(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) ? v.GetString() ?? throw new JsonException($"null '{name}'")
            : throw new JsonException($"missing string '{name}'");
}

public sealed class ShapePathConverter : JsonConverter<ShapePath>
{
    public override ShapePath Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var e = doc.RootElement;
        return JsonReadHelpers.TypeOf(e) switch
        {
            "roundedRect" => new RoundedRect(
                JsonReadHelpers.Req<Rect>(e, "rect", o), JsonReadHelpers.Num(e, "radius")),
            "ellipse" => new Ellipse(JsonReadHelpers.Req<Rect>(e, "rect", o)),
            "polygon" => new Polygon(JsonReadHelpers.Req<List<Point>>(e, "points", o)),
            "path" => new PathShape(JsonReadHelpers.Req<List<PathVerb>>(e, "verbs", o)),
            var other => throw new JsonException($"unknown ShapePath type '{other}'"),
        };
    }
    public override void Write(Utf8JsonWriter w, ShapePath v, JsonSerializerOptions o) =>
        throw new NotSupportedException("SceneWire is read-only in .NET");
}

public sealed class PathVerbConverter : JsonConverter<PathVerb>
{
    public override PathVerb Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var e = doc.RootElement;
        return JsonReadHelpers.TypeOf(e) switch
        {
            "move" => new MoveVerb(JsonReadHelpers.Req<Point>(e, "point", o)),
            "line" => new LineVerb(JsonReadHelpers.Req<Point>(e, "point", o)),
            "quad" => new QuadVerb(
                JsonReadHelpers.Req<Point>(e, "to", o), JsonReadHelpers.Req<Point>(e, "control", o)),
            "close" => new CloseVerb(),
            var other => throw new JsonException($"unknown PathVerb type '{other}'"),
        };
    }
    public override void Write(Utf8JsonWriter w, PathVerb v, JsonSerializerOptions o) =>
        throw new NotSupportedException("SceneWire is read-only in .NET");
}

public sealed class ElementConverter : JsonConverter<Element>
{
    public override Element Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var e = doc.RootElement;
        return JsonReadHelpers.TypeOf(e) switch
        {
            "shape" => new ShapeElement(
                JsonReadHelpers.Req<ShapePath>(e, "path", o),
                JsonReadHelpers.Opt<string>(e, "fill", o),
                JsonReadHelpers.Opt<Stroke>(e, "stroke", o)),
            "polyline" => new PolylineElement(
                JsonReadHelpers.Req<List<Point>>(e, "points", o),
                JsonReadHelpers.Req<Stroke>(e, "stroke", o),
                JsonReadHelpers.Flag(e, "startArrow"),
                JsonReadHelpers.Flag(e, "endArrow")),
            "text" => new TextElement(
                JsonReadHelpers.Str(e, "string"),
                JsonReadHelpers.Req<Point>(e, "center", o),
                JsonReadHelpers.Num(e, "fontSize"),
                JsonReadHelpers.Str(e, "weight"),
                JsonReadHelpers.Str(e, "color"),
                JsonReadHelpers.Opt<string>(e, "backing", o),
                e.TryGetProperty("rotation", out var r) ? r.GetDouble() : 0.0),
            var other => throw new JsonException($"unknown Element type '{other}'"),
        };
    }
    public override void Write(Utf8JsonWriter w, Element v, JsonSerializerOptions o) =>
        throw new NotSupportedException("SceneWire is read-only in .NET");
}
