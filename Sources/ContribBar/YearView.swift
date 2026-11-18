import SwiftUI

/// The classic GitHub contribution grid, drawn in a Canvas with hover details.
struct YearView: View {
    let snapshot: ContributionSnapshot
    let width: CGFloat

    @State private var hovered: ContributionDay?

    private let gap: CGFloat = 2
    private let labelWidth: CGFloat = 28
    private let headerHeight: CGFloat = 16

    var body: some View {
        let columns = snapshot.weekColumns
        let cell = ((width - labelWidth) - gap * CGFloat(columns.count - 1)) / CGFloat(max(columns.count, 1))
        let step = cell + gap
        let height = headerHeight + step * 7 - gap

        VStack(alignment: .leading, spacing: 10) {
            Canvas { context, _ in
                // Month labels: at the first week column that starts in a new month.
                var lastMonth: Int?
                var lastLabelX = -CGFloat.infinity
                for (index, week) in columns.enumerated() {
                    guard let first = week.compactMap({ $0 }).first else { continue }
                    let month = Calendar.current.component(.month, from: first.day)
                    defer { lastMonth = month }
                    guard month != lastMonth else { continue }
                    let x = labelWidth + CGFloat(index) * step
                    guard x - lastLabelX > 26 else { continue }  // avoid overlapping a partial first month
                    lastLabelX = x
                    context.draw(
                        Text(first.day, format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.secondary),
                        at: CGPoint(x: x, y: 0),
                        anchor: .topLeading
                    )
                }

                // Weekday labels on Mon/Wed/Fri rows, like GitHub.
                for (row, name) in [(1, "Mon"), (3, "Wed"), (5, "Fri")] {
                    context.draw(
                        Text(name).font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: 0, y: headerHeight + CGFloat(row) * step + cell / 2),
                        anchor: .leading
                    )
                }

                for (col, week) in columns.enumerated() {
                    for (row, day) in week.enumerated() {
                        guard let day else { continue }
                        let rect = CGRect(
                            x: labelWidth + CGFloat(col) * step,
                            y: headerHeight + CGFloat(row) * step,
                            width: cell,
                            height: cell
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 2)
                        context.fill(path, with: .color(Palette.color(day.contributionLevel)))
                        if day == hovered {
                            context.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: 1.5)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let col = Int(((point.x - labelWidth) / step).rounded(.down))
                    let row = Int(((point.y - headerHeight) / step).rounded(.down))
                    hovered = columns.indices.contains(col) && (0..<7).contains(row) ? columns[col][row] : nil
                case .ended:
                    hovered = nil
                }
            }

            HStack {
                Group {
                    if let day = hovered {
                        Text("\(day.contributionCount.contributionsLabel) on \(day.day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())")
                    } else {
                        Text("Hover over a day for details")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 3) {
                    Text("Less").padding(.trailing, 2)
                    ForEach(ContributionLevel.allCases, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.color(level))
                            .frame(width: 10, height: 10)
                    }
                    Text("More").padding(.leading, 2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                StatTile(title: "Current streak", value: "\(snapshot.currentStreak) days", symbol: "flame.fill")
                StatTile(title: "Longest streak", value: "\(snapshot.longestStreak) days", symbol: "trophy.fill")
                StatTile(
                    title: "Active days",
                    value: "\(RangeStats(snapshot.days).activeDays) / \(snapshot.days.count)",
                    symbol: "calendar"
                )
            }
        }
    }
}
