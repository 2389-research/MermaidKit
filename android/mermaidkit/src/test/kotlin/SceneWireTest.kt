import ai.mermaidkit.scene.*
import kotlinx.serialization.encodeToString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/// Proves the payoff of the explicit wire schema: the EXACT JSON `mmk_scene_json`
/// emits (captured as golden fixtures) deserializes in Kotlin with plain
/// @Serializable data classes and no custom serializers.
class SceneWireTest {

    private fun load(name: String): String =
        checkNotNull(javaClass.getResource("/$name.json")) { "$name.json missing" }.readText()

    @Test
    fun parsesFlowchartWithNoCustomSerializers() {
        val scene = SceneWire.parse(load("flowchart"))
        assertEquals(1, scene.version)
        assertTrue(scene.background.startsWith("#"), "background is a hex string")
        assertTrue(scene.elements.isNotEmpty())

        // The `type` discriminator lands each element on the right subclass.
        assertTrue(scene.elements.any { it is Element.Polyline }, "expected routed edges")
        assertTrue(scene.elements.any { it is Element.Shape }, "expected node shapes")
        assertTrue(scene.elements.any { it is Element.Text }, "expected labels")

        // Nested discriminated geometry decodes too: this flowchart has a
        // rounded rect (rect node), a polygon (diamond), and an ellipse (circle).
        val paths = scene.elements.filterIsInstance<Element.Shape>().map { it.path }
        assertTrue(paths.any { it is ShapePath.RoundedRect }, "rect node → RoundedRect")
        assertTrue(paths.any { it is ShapePath.Polygon }, "diamond → Polygon")
        assertTrue(paths.any { it is ShapePath.Ellipse }, "circle → Ellipse")

        // A polyline carries real points + an arrow flag.
        val edge = scene.elements.filterIsInstance<Element.Polyline>().first()
        assertTrue(edge.points.size >= 2)
        assertTrue(edge.endArrow)
    }

    @Test
    fun reEncodeIsStructurallyStable() {
        val scene = SceneWire.parse(load("flowchart"))
        val reencoded = SceneWire.json.encodeToString(scene)
        // Field order differs from Swift's sortedKeys, so compare structurally.
        assertEquals(scene, SceneWire.parse(reencoded))
    }

    @Test
    fun parsesSequenceDiagram() {
        val scene = SceneWire.parse(load("sequence"))
        assertTrue(scene.elements.isNotEmpty())
        assertTrue(scene.elements.any { it is Element.Text })
    }

    @Test
    fun toleratesUnknownFields() {
        // A newer producer adds a field the reader doesn't know — must not throw.
        val forward = """{"version":2,"size":{"w":1,"h":1},"background":"#FFFFFFFF",
            "futureField":true,"elements":[]}"""
        val scene = SceneWire.parse(forward)
        assertEquals(2, scene.version)
    }
}
