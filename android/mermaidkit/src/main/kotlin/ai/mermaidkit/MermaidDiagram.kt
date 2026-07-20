package ai.mermaidkit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import ai.mermaidkit.scene.SceneRenderer

/**
 * Render a Mermaid diagram from a **source string** in Compose — the snap-in
 * surface. The whole pipeline (native parse → `SceneWire` → `Canvas` draw) sits
 * behind one composable:
 *
 * ```
 * MermaidDiagram("flowchart LR\n A[Start] --> B[End]", Modifier.fillMaxWidth())
 * ```
 *
 * The diagram sizes to the width it's given, preserving the scene's aspect ratio,
 * and its accessibility narration is exposed as the node's `contentDescription`.
 * [theme] defaults to the app's Material colors (`MermaidTheme.fromMaterial`), so
 * the diagram matches the surrounding UI — including light/dark — with no extra
 * wiring. Nothing is drawn for blank or unparseable source.
 *
 * Text is measured with the same face that draws (via [PaintMeasurer]), so
 * layout and draw agree.
 */
@Composable
fun MermaidDiagram(
    source: String,
    modifier: Modifier = Modifier,
    theme: MermaidTheme = MermaidTheme.fromMaterial(MaterialTheme.colorScheme),
) {
    val scene = remember(source, theme) {
        source.takeIf { it.isNotBlank() }
            ?.let { MermaidNative.scene(it, theme, PaintMeasurer()) }
    }
    val narration = remember(source) {
        source.takeIf { it.isNotBlank() }?.let { MermaidNative.narrate(it) }
    }
    val renderer = remember { SceneRenderer() }

    if (scene == null || scene.size.w <= 0 || scene.size.h <= 0) return

    val aspect = (scene.size.w / scene.size.h).toFloat()
    Canvas(
        modifier
            .aspectRatio(aspect)
            .semantics { narration?.let { contentDescription = it } }
    ) {
        val scale = size.width / scene.size.w.toFloat()
        drawIntoCanvas { canvas ->
            val native = canvas.nativeCanvas
            val save = native.save()
            native.scale(scale, scale)
            renderer.draw(scene, native)
            native.restoreToCount(save)
        }
    }
}
