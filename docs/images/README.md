# App images

These images capture the app's native views with synthetic usage data, at 2× scale:

- `menu-bar.png`: the actual `NSStatusBarButton`, isolated on a neutral dark backing.
- `usage-panel.png`: the stock `CostPanel`, rendered by SwiftUI `ImageRenderer` with its normal light appearance on a neutral backing. It shows four models today and five this month, including the native Restart and Quit controls.

Captured October 12, 2026 from the integrated UI at `49c03aba21148c63ee6c10b361c7d839ef1a87e0`. The panel used native view rendering because desktop screen capture was unavailable. No mockup, overlaid text, personal usage logs, or unrelated menu items are included.

The sample logs contain only made-up session/message identifiers and token counts. All four log roots were explicitly set to isolated temporary directories. The diagnostic report contained 17 sample files, zero diagnostics, and zero unpriced records; Today totaled $11.39 and This Month totaled $45.6152 (displayed as $45.62). Capture-only instrumentation stayed outside the repository; the app source was not changed for these images.
