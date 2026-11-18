import Foundation

/// Reads a user's public contribution graph from github.com — no token required.
/// This is the same HTML fragment the profile page loads, so it only includes what the profile shows publicly.
enum PublicContributions {
    enum FetchError: LocalizedError {
        case userNotFound(String)
        case http(Int)
        case unrecognizedPage

        var errorDescription: String? {
            switch self {
            case .userNotFound(let login): "GitHub user “\(login)” not found."
            case .http(let code): "GitHub returned HTTP \(code)."
            case .unrecognizedPage: "Couldn't read the contribution graph — GitHub may have changed its page."
            }
        }
    }

    static func fetchSnapshot(login: String, now: Date = .now) async throws -> ContributionSnapshot {
        guard let path = login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://github.com/users/\(path)/contributions")
        else { throw FetchError.userNotFound(login) }

        var request = URLRequest(url: url)
        request.setValue("ContribBar", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw FetchError.userNotFound(login) }
        guard (200..<300).contains(status) else { throw FetchError.http(status) }

        let days = try parse(String(decoding: data, as: UTF8.self))
        // Match the GraphQL path: the last 365 days, ending today.
        let calendar = Calendar.current
        let start = DayFormat.string(calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))!)
        let inRange = days.filter { $0.date >= start }

        return ContributionSnapshot(
            login: login,
            totalContributions: inRange.reduce(0) { $0 + $1.contributionCount },
            weeks: [ContributionWeek(contributionDays: inRange)],
            fetchedAt: now
        )
    }

    /// Cells look like `<td data-date="2026-11-16" id="contribution-day-component-1-0" data-level="2" …>`,
    /// with counts in a matching `<tool-tip for="contribution-day-component-1-0">5 contributions on …</tool-tip>`.
    static func parse(_ html: String) throws -> [ContributionDay] {
        var counts: [String: Int] = [:]
        for match in html.matches(of: #/<tool-tip[^>]*\bfor="([^"]+)"[^>]*>([^<]*)<\/tool-tip>/#) {
            let text = match.output.2
            let leadingNumber = text.prefix { $0.isNumber || $0 == "," }.filter(\.isNumber)
            counts[String(match.output.1)] = Int(leadingNumber) ?? 0  // "No contributions on …" → 0
        }

        let days: [ContributionDay] = html.matches(of: #/<td[^>]*ContributionCalendar-day[^>]*>/#).compactMap { match in
            let tag = String(match.output)
            guard let date = attribute("data-date", in: tag),
                  let id = attribute("id", in: tag),
                  let level = attribute("data-level", in: tag).flatMap(Int.init)
            else { return nil }
            return ContributionDay(
                date: date,
                contributionCount: counts[id] ?? 0,
                contributionLevel: ContributionLevel.allCases[min(max(level, 0), 4)]
            )
        }
        guard !days.isEmpty else { throw FetchError.unrecognizedPage }
        return days.sorted { $0.date < $1.date }  // the table is laid out row-by-weekday
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=\"") else { return nil }
        let rest = tag[range.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }
}
