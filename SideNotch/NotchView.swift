import SwiftUI

/// Redraws the notch whenever `UsageMonitor` publishes new numbers or the panel
/// is collapsed/expanded.
struct NotchRootView: View {
    let monitor: UsageMonitor
    let state: PanelState

    var body: some View {
        NotchView(metrics: monitor.metrics, state: state)
    }
}

/// Everything the panel draws: the black bar on the right (or the tab it hides
/// behind), and the hover card floating to its left. The panel is deliberately
/// larger than the bar so the card and the shadows have room; the extra area is
/// transparent and, thanks to `PassthroughView`, does not swallow clicks meant
/// for the windows below.
struct NotchView: View {
    let metrics: [Metric]
    let state: PanelState

    @State private var hovered: Int?
    @State private var tabHovered = false

    /// `previewHover` pins a ring as hovered so the card can be rendered
    /// offscreen (snapshots, previews); it is nil in the running app.
    init(metrics: [Metric],
         state: PanelState = PanelState(expanded: true),
         previewHover: Int? = nil) {
        self.metrics = metrics
        self.state = state
        _hovered = State(initialValue: previewHover)
    }

    private var expanded: Bool { state.isExpanded }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if expanded, let index = hovered, metrics.indices.contains(index) {
                DetailCard(metric: metrics[index],
                           tailCenterY: Layout.ringCenterY(index) - (cardCenterY(for: index) - Layout.cardHeight / 2))
                    .frame(width: Layout.cardWidth + Layout.tailWidth,
                           height: Layout.cardHeight)
                    .position(x: cardCenterX, y: cardCenterY(for: index))
                    .transition(.opacity.combined(with: .offset(x: 10)))
                    .allowsHitTesting(false)
            }

            bar
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded { hovered = nil }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: expanded)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: tabHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: hovered)
    }

    // MARK: - The bar, in both of its sizes

    private var bar: some View {
        rings
            .opacity(expanded ? 1 : 0)
            .allowsHitTesting(expanded)
            .frame(width: barWidth, height: barHeight)
            .background { barShape.fill(Color.black) }
            .clipShape(barShape)
            .overlay { grip }
            .shadow(color: .black.opacity(0.35), radius: expanded ? 14 : 8, x: -5, y: 0)
            .contentShape(barShape)
            .onTapGesture { toggle() }
            .onHover { inside in tabHovered = inside && !expanded }
            .position(x: Layout.panelWidth - barWidth / 2, y: Layout.contentCenterY)
    }

    private var rings: some View {
        VStack(spacing: Layout.ringSpacing) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                RingView(metric: metric, isHighlighted: hovered == index)
                    .onHover { inside in
                        guard expanded else { return }
                        if inside {
                            hovered = index
                        } else if hovered == index {
                            hovered = nil
                        }
                    }
            }
        }
        .padding(.vertical, Layout.notchVerticalPadding)
    }

    /// The little handle that says "there is something here".
    private var grip: some View {
        Capsule()
            .fill(Color.white.opacity(tabHovered ? 0.6 : 0.3))
            .frame(width: 2, height: 26)
            .opacity(expanded ? 0 : 1)
    }

    private var barWidth: CGFloat {
        guard !expanded else { return Layout.notchWidth }
        return tabHovered ? Layout.tabHoverWidth : Layout.tabWidth
    }

    private var barHeight: CGFloat {
        expanded ? Layout.notchShapeHeight : Layout.tabHeight
    }

    private var barShape: NotchShape {
        NotchShape(cornerRadius: expanded ? Layout.notchCornerRadius : Layout.tabCornerRadius,
                   filletRadius: expanded ? Layout.filletRadius : Layout.tabFilletRadius)
    }

    private func toggle() {
        if expanded { hovered = nil }
        tabHovered = false
        state.toggle()
    }

    // MARK: - Card placement

    private var cardCenterX: CGFloat {
        Layout.panelWidth - Layout.notchWidth - Layout.cardGap
            - (Layout.cardWidth + Layout.tailWidth) / 2
    }

    /// Centred on the hovered ring, but never poking above the notch (and so
    /// never over the menu bar) or below its bottom edge.
    private func cardCenterY(for index: Int) -> CGFloat {
        let half = Layout.cardHeight / 2
        let top = Layout.shadowPad + half
        let bottom = Layout.shadowPad + Layout.notchShapeHeight - half
        return min(max(Layout.ringCenterY(index), top), bottom)
    }
}
