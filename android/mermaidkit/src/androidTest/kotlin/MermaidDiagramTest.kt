package ai.mermaidkit

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Compose snap-in surface: [MermaidDiagram] composes from a source string and
 * exposes the diagram's narration as `contentDescription` semantics — so it both
 * renders and is screen-reader-navigable from the very first surface. Needs the
 * cross-compiled jniLibs (the composable parses natively).
 */
@RunWith(AndroidJUnit4::class)
class MermaidDiagramTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun composesAndExposesNarrationSemantics() {
        compose.setContent {
            MermaidDiagram(
                source = "flowchart LR\n A[Start] --> B{Choice}\n B --> C((Done))",
                modifier = Modifier.fillMaxWidth())
        }
        // The narration walkthrough mentions the node labels; assert the semantics
        // node carrying it exists (proving both compose + a11y wiring).
        compose.onNodeWithContentDescription("Start", substring = true).assertExists()
    }
}
