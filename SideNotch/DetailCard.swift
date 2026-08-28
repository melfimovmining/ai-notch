import SwiftUI

/// The hover card: header, then one progress bar per usage row.
struct DetailCard: View {
    let metric: Metric
    /// Tail centre, measured from the top of the card.
    let tailCenterY: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                Text(metric.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            ForEach(metric.rows) { row in
                UsageRowView(row: row)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 18 + Layout.tailWidth)
        .padding(.vertical, 16)
        .frame(width: Layout.cardWidth + Layout.tailWidth, alignment: .leading)
        .background {
            CardShape(tailCenterY: tailCenterY)
                .fill(Color.black)
                .overlay {
                    CardShape(tailCenterY: tailCenterY)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, x: -4, y: 8)
        }
    }
}

private struct UsageRowView: View {
    let row: UsageRow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
                Text(row.meta)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
            }

            ProgressBar(value: row.value, tint: row.tint)

            Text(row.caption)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}
