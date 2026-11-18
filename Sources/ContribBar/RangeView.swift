import Charts
import SwiftUI

/// Shared view for the 7-day and 30-day tabs: summary tiles plus a hoverable bar chart.
struct RangeView: View {
    enum Kind { case week, month }

    let days: [ContributionDay]
    let kind: Kind
    @State private var hoveredKey: String?

    private var hoveredDay: ContributionDay? {
        days.first { $0.date == hoveredKey }
    }

    /// Which day keys get an x-axis label: every day for a week, every 5th (ending today) for a month.
    private var labeledKeys: [String] {
        switch kind {
        case .week: days.map(\.date)
        case .month: days.reversed().enumerated().filter { $0.offset % 5 == 0 }.map(\.element.date)
        }
    }

    var body: some View {
        let stats = RangeStats(days)
        let yMax = max(Int((Double(stats.best?.contributionCount ?? 0) * 1.2).rounded(.up)), 4)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatTile(title: "Total", value: stats.total.formatted(), symbol: "sum")
                StatTile(
                    title: "Daily average",
                    value: stats.average.formatted(.number.precision(.fractionLength(1))),
                    symbol: "chart.line.uptrend.xyaxis"
                )
                StatTile(title: "Active days", value: "\(stats.activeDays) / \(days.count)", symbol: "calendar")
                StatTile(title: "Best day", value: bestLabel(stats.best), symbol: "star.fill")
            }

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date),  // categorical, so labels center under bars
                    y: .value("Contributions", day.contributionCount)
                )
                .foregroundStyle(Palette.color(day.contributionLevel == .none ? .first : day.contributionLevel))
                .cornerRadius(3)
                .opacity(hoveredDay == nil || hoveredDay == day ? 1 : 0.45)
                .annotation(position: .top, spacing: 2) {
                    if kind == .week && day.contributionCount > 0 {
                        Text("\(day.contributionCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartXSelection(value: $hoveredKey)
            .chartXAxis { xAxis }
            .frame(height: 140)

            Group {
                if let day = hoveredDay {
                    Text("\(day.contributionCount.contributionsLabel) on \(day.day, format: .dateTime.weekday(.wide).month(.abbreviated).day())")
                } else {
                    Text("Hover over a bar for details")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var xAxis: some AxisContent {
        // Category axes label every value regardless of `values:`, so filter inside the label.
        let shown = Set(labeledKeys)
        return AxisMarks { value in
            AxisValueLabel {
                if let key = value.as(String.self), shown.contains(key), let date = DayFormat.date(from: key) {
                    Text(date, format: kind == .week ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                }
            }
        }
    }

    private func bestLabel(_ day: ContributionDay?) -> String {
        guard let day else { return "–" }
        let date = day.day.formatted(kind == .week ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
        return "\(day.contributionCount) · \(date)"
    }
}
