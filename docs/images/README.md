# App images

`usage-panel.png` captures the current shared `CostPanelContent` in a native AppKit window at the production 280-point width and 2× scale, in light appearance with automatic update checks enabled. It shows Today and This Month totals, one row per model (including an Unpriced model), the subtle update controls, and Restart and Quit actions.

Captured October 17, 2026 from commit `d6620b4` using:

```sh
SWIFT_TOOL=scripts/swift-tool.sh scripts/preview-ui.sh
```

The README image is the harness output `light-auto-on.png`. Totals are synthetic ($2.46 today and $57.03 this month), and version `0.0.0` identifies the preview. The harness renders the same native content as the live panel without reading personal logs or preferences, starting Sparkle, or replacing the installed app. It captures panel content, not the menu-bar anchor or popover material. See [native UI validation](../ui-validation.md) for the workflow and limits.

`menu-bar.png` is an older capture of the actual `NSStatusBarButton`, isolated on a neutral dark backing. It was captured October 12, 2026 with synthetic usage data and is not displayed in the README.
