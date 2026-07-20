@file:OptIn(ExperimentalSerializationApi::class)

package ai.mermaidkit.scene

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonClassDiscriminator

// The Kotlin twin of Swift's `SceneWire` — the explicit, language-neutral wire
// schema `mmk_scene_json` emits. Because the schema is flat and `type`-tagged,
// this is a plain sealed hierarchy: kotlinx.serialization reads it with ZERO
// custom serializers. Colors are `#RRGGBBAA` strings (parse when drawing);
// coordinates are points in a top-left-origin space (y grows downward).

@Serializable
data class Point(val x: Double, val y: Double)

@Serializable
data class Size(val w: Double, val h: Double)

@Serializable
data class Rect(val x: Double, val y: Double, val w: Double, val h: Double)

@Serializable
data class Stroke(val color: String, val width: Double, val dashed: Boolean = false)

/// A shape outline, discriminated on `type`.
@Serializable
@JsonClassDiscriminator("type")
sealed interface ShapePath {
    @Serializable @SerialName("roundedRect")
    data class RoundedRect(val rect: Rect, val radius: Double) : ShapePath

    @Serializable @SerialName("ellipse")
    data class Ellipse(val rect: Rect) : ShapePath

    @Serializable @SerialName("polygon")
    data class Polygon(val points: List<Point>) : ShapePath

    @Serializable @SerialName("path")
    data class Path(val verbs: List<PathVerb>) : ShapePath
}

/// One command in an arbitrary outline, discriminated on `type`.
@Serializable
@JsonClassDiscriminator("type")
sealed interface PathVerb {
    @Serializable @SerialName("move") data class Move(val point: Point) : PathVerb
    @Serializable @SerialName("line") data class Line(val point: Point) : PathVerb
    @Serializable @SerialName("quad") data class Quad(val to: Point, val control: Point) : PathVerb
    @Serializable @SerialName("close") data object Close : PathVerb
}

/// One display-list item, discriminated on `type`.
@Serializable
@JsonClassDiscriminator("type")
sealed interface Element {
    @Serializable @SerialName("shape")
    data class Shape(
        val path: ShapePath,
        val fill: String? = null,
        val stroke: Stroke? = null,
    ) : Element

    @Serializable @SerialName("polyline")
    data class Polyline(
        val points: List<Point>,
        val stroke: Stroke,
        val startArrow: Boolean = false,
        val endArrow: Boolean = false,
    ) : Element

    @Serializable @SerialName("text")
    data class Text(
        val string: String,
        val center: Point,
        val fontSize: Double,
        val weight: String,
        val color: String,
        val backing: String? = null,
        val rotation: Double = 0.0,
    ) : Element
}

/// A fully-resolved, platform-free display list. Paint `elements` in order
/// (first painted first, later on top) after filling `background`.
@Serializable
data class SceneWire(
    val version: Int,
    val size: Size,
    val background: String,
    val elements: List<Element>,
) {
    companion object {
        /// The current schema revision this reader targets. A payload with a
        /// higher `version` still decodes (unknown fields are ignored), but a
        /// consumer may want to warn.
        const val SUPPORTED_VERSION = 1

        /// The configured decoder: tolerant of unknown keys so a newer producer
        /// (extra fields) never breaks an older reader.
        val json: Json = Json { ignoreUnknownKeys = true }

        /// Parse wire JSON (e.g. the string from `mmk_scene_json`) into a scene.
        fun parse(text: String): SceneWire = json.decodeFromString(text)
    }
}
