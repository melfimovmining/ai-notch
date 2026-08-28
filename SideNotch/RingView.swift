import SwiftUI

/// A circular progress ring with a centred icon and the percentage underneath.
struct RingView: View {
    let metric: Metric
    var isHighlighted: Bool = false

    var body: some View {
        VStack(spacing: Layout.percentTopGap) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.11))

                Circle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)

                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(Color.white.opacity(0.10),
                            style: StrokeStyle(lineWidth: Layout.ringLineWidth, lineCap: .round))
                    .padding(Layout.ringLineWidth / 2)

                Circle()
                    .trim(from: 0, to: max(0.001, min(metric.value, 1)))
                    .stroke(metric.tint,
                            style: StrokeStyle(lineWidth: Layout.ringLineWidth, lineCap: .round))
                    .padding(Layout.ringLineWidth / 2)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: metric.tint.opacity(isHighlighted ? 0.55 : 0.25), radius: 6)

                Image(systemName: metric.symbol)
                    .font(.system(size: Layout.ringIconSize, weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: Layout.ringDiameter, height: Layout.ringDiameter)
            .scaleEffect(isHighlighted ? 1.06 : 1)

            Text(metric.percentText)
                .font(.system(size: Layout.percentFontSize, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isHighlighted ? 1 : 0.92))
        }
        .frame(width: Layout.notchWidth, height: Layout.itemHeight)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHighlighted)
    }
}
