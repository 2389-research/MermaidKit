# Theming

Every color a diagram wears comes from one value: ``DiagramTheme``. Replace
it to re-skin all 30 diagram types at once.

## Anatomy of a theme

| Field | What wears it |
|---|---|
| `ink` | Primary text: node labels, titles, axis values |
| `secondaryTextColor` | Edge labels, captions, legends |
| `tertiaryTextColor` | De-emphasized text: type tags, ticks, watermarks |
| `canvas` | The background — also the "chip" behind edge labels, so it must match what the diagram sits on |
| `accent` | Highlights: active states, links, emphasis |
| `hairline` | Rules and borders: table lines, axes, lifelines |
| `palette` | **Categorical accents** — node tints, pie slices, sankey bands, gantt sections, git branches, cycled by index |
| `prefersDark` | Keys the render cache and dark-tuned alpha choices |

## The two built-in appearances

```swift
DiagramTheme(prefersDark: false)   // light
DiagramTheme(prefersDark: true)    // dark
```

These use MermaidKit's defaults: near-black/near-white ink, white/#1B1B1D
canvas, the system accent, and ``DiagramTheme/defaultPalette`` (six hues
tuned to stay distinct on both appearances).

## A brand theme

```swift
extension NSColor {
    // NSColor has no hex initializer; this convenience keeps the example concise.
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension DiagramTheme {
    static func brand(dark: Bool) -> DiagramTheme {
        DiagramTheme(
            ink: dark ? .white : NSColor(hex: 0x101418),
            secondaryTextColor: .secondaryLabelColor,
            tertiaryTextColor: .tertiaryLabelColor,
            canvas: dark ? NSColor(hex: 0x0D1117) : .white,
            accent: NSColor(hex: 0x0A84FF),
            hairline: .separatorColor,
            prefersDark: dark,
            palette: [
                NSColor(hex: 0x0A84FF), NSColor(hex: 0x30D158),
                NSColor(hex: 0xFF9F0A), NSColor(hex: 0xFF375F),
                NSColor(hex: 0xBF5AF2), NSColor(hex: 0x64D2FF),
            ]
        )
    }
}

MermaidView(source, theme: .brand(dark: colorScheme == .dark))
```

Two rules of thumb:

- **`canvas` must match the surface the diagram sits on.** Edge labels are
  drawn on a canvas-colored chip that masks the line beneath them; if the
  canvas color doesn't match your background, the chips show as rectangles.
- **Palette colors are used at reduced alpha for fills** (nodes tint at
  ~10–25% alpha with a stronger border), so pick saturated hues — they'll
  soften on the page.

## Monochrome

An empty-ish palette is legitimate: with `palette: [accent]` every
categorical element wears one hue and diagrams read as single-color
line art.

## How the host app should wire appearance

Follow the environment (what ``MermaidView`` does by default), or key your
own theme off your app's appearance system and pass it explicitly. The
render cache keys on `prefersDark`, so flipping appearance re-renders
correctly without cache pollution.
