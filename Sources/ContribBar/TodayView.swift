import SwiftUI

struct TodayView: View {
    let snapshot: ContributionSnapshot

    var body: some View {
        let today = snapshot.today
        let month = RangeStats(snapshot.last(30))

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(today.day, format: .dateTime.weekday(.wide).month(.wide).day())
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.color(today.contributionLevel))
                        .frame(width: 22, height: 22)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text("\(today.contributionCount)")
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(today.contributionCount == 1 ? "contribution" : "contributions")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let yesterday = snapshot.yesterday {
                    comparison(today.contributionCount - yesterday.contributionCount, against: "yesterday")
                }
                comparison(
                    Int((Double(today.contributionCount) - month.average).rounded()),
                    against: "the 30-day average (\(month.average.formatted(.number.precision(.fractionLength(1)))))"
                )
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                StatTile(title: "Current streak", value: days(snapshot.currentStreak), symbol: "flame.fill")
                StatTile(title: "Longest streak (year)", value: days(snapshot.longestStreak), symbol: "trophy.fill")
                StatTile(title: "Active days (30d)", value: "\(month.activeDays) / 30", symbol: "calendar")
            }
            .frame(width: 220)
        }
    }

    private func comparison(_ delta: Int, against reference: String) -> some View {
        let (symbol, text): (String, String) = switch delta {
        case 0: ("equal", "Same as \(reference)")
        case 1...: ("arrow.up.right", "\(delta) more than \(reference)")
        default: ("arrow.down.right", "\(-delta) fewer than \(reference)")
        }
        return Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(delta > 0 ? AnyShapeStyle(Palette.color(.third)) : AnyShapeStyle(.secondary))
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
}
