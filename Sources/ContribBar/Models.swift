import Foundation

enum ContributionLevel: String, Decodable, CaseIterable, Sendable {
    case none = "NONE"
    case first = "FIRST_QUARTILE"
    case second = "SECOND_QUARTILE"
    case third = "THIRD_QUARTILE"
    case fourth = "FOURTH_QUARTILE"
}

struct ContributionDay: Decodable, Identifiable, Hashable, Sendable {
    let date: String  // yyyy-MM-dd, in the local timezone we query with
    let contributionCount: Int
    let contributionLevel: ContributionLevel

    var id: String { date }
    var day: Date { DayFormat.date(from: date) ?? .distantPast }
}

struct ContributionWeek: Decodable, Sendable {
    let contributionDays: [ContributionDay]
}

struct ContributionSnapshot: Sendable {
    let login: String
    let totalContributions: Int
    let fetchedAt: Date
    /// Chronological, contiguous days ending at local today (today is always present).
    let days: [ContributionDay]

    init(login: String, totalContributions: Int, weeks: [ContributionWeek], fetchedAt: Date) {
        self.login = login
        self.totalContributions = totalContributions
        self.fetchedAt = fetchedAt
        let today = DayFormat.string(fetchedAt)
        var days = weeks.flatMap(\.contributionDays).filter { $0.date <= today }
        if days.last?.date != today {
            days.append(ContributionDay(date: today, contributionCount: 0, contributionLevel: .none))
        }
        self.days = days
    }

    var today: ContributionDay { days[days.count - 1] }
    var yesterday: ContributionDay? { days.dropLast().last }

    func last(_ n: Int) -> [ContributionDay] { Array(days.suffix(n)) }

    /// Consecutive active days ending today — or yesterday, so a streak isn't "broken" before you've had a chance to commit today.
    var currentStreak: Int {
        var recent = days.reversed()[...]
        if recent.first?.contributionCount == 0 { recent = recent.dropFirst() }
        return recent.prefix { $0.contributionCount > 0 }.count
    }

    var longestStreak: Int {
        var best = 0, run = 0
        for day in days {
            run = day.contributionCount > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// Days laid out GitHub-style: one column per week, Sunday at index 0. Padding cells are nil.
    var weekColumns: [[ContributionDay?]] {
        guard let first = days.first else { return [] }
        let leading = Calendar.current.component(.weekday, from: first.day) - 1  // weekday 1 == Sunday
        let cells: [ContributionDay?] = Array(repeating: nil, count: leading) + days.map(Optional.some)
        return stride(from: 0, to: cells.count, by: 7).map { start in
            let week = Array(cells[start..<min(start + 7, cells.count)])
            return week + Array(repeating: nil, count: 7 - week.count)
        }
    }
}

struct RangeStats {
    let total: Int
    let activeDays: Int
    let average: Double
    let best: ContributionDay?

    init(_ days: [ContributionDay]) {
        total = days.reduce(0) { $0 + $1.contributionCount }
        activeDays = days.filter { $0.contributionCount > 0 }.count
        average = days.isEmpty ? 0 : Double(total) / Double(days.count)
        best = days.max { $0.contributionCount < $1.contributionCount }.flatMap { $0.contributionCount > 0 ? $0 : nil }
    }
}

enum DayFormat {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}
