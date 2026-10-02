import SwiftUI

/// The floating cluster over the canvas (FR-CNV-08): zoom, fit and add topic
/// in one `GlassEffectContainer`, the only glass on the canvas. Each control
/// is also a menu item with the same name, the AI menu included.
struct CanvasControls: View {
    let model: CanvasModel

    var body: some View {
        GlassEffectContainer(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                control("Zoom Out", systemImage: "minus.magnifyingglass", enabled: model.canZoomOut, action: model.zoomOut)
                Button(action: model.zoomToActualSize) {
                    Text(Double(model.viewport.scale), format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: Metrics.zoomLabelWidth, minHeight: Metrics.minimumHitTarget)
                }
                .help(Text("Actual Size"))
                .accessibilityLabel(Text("Actual Size"))
                .accessibilityValue(Text(Double(model.viewport.scale), format: .percent.precision(.fractionLength(0))))
                control("Zoom In", systemImage: "plus.magnifyingglass", enabled: model.canZoomIn, action: model.zoomIn)
                control("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right", enabled: model.canZoomToFit, action: model.zoomToFit)
                control("Add Child Topic", systemImage: "arrow.turn.down.right", enabled: true, action: model.session.addChild)
                if let assistant = model.assistant, assistant.service.showsControls {
                    Menu {
                        AIActionsMenu(assistant: assistant, includesGenerateMap: true)
                    } label: {
                        Label {
                            Text("AI")
                        } icon: {
                            AISymbol()
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                    }
                    .menuIndicator(.hidden)
                    .help(Text("AI"))
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func control(_ title: LocalizedStringKey, systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
        }
        .disabled(!enabled)
        .help(Text(title))
    }
}
