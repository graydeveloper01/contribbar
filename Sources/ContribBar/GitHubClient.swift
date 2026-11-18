import Foundation

struct GitHubClient {
    let token: String

    enum ClientError: LocalizedError {
        case unauthorized
        case http(Int)
        case api(String)
        case noData
        case userNotFound(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "GitHub rejected the token. Update it in Settings."
            case .http(let code): "GitHub returned HTTP \(code)."
            case .api(let message): message
            case .noData: "GitHub returned no contribution data."
            case .userNotFound(let login): "GitHub user “\(login)” not found."
            }
        }
    }

    /// `root` is either `viewer` (the token's own account) or `user(login: $login)`.
    private static func query(root: String, declaresLogin: Bool) -> String {
        """
        query($from: DateTime!, $to: DateTime!\(declaresLogin ? ", $login: String!" : "")) {
          account: \(root) {
            login
            contributionsCollection(from: $from, to: $to) {
              contributionCalendar {
                totalContributions
                weeks { contributionDays { date contributionCount contributionLevel } }
              }
            }
          }
        }
        """
    }

    /// Fetches the last 365 days. Day boundaries follow the timezone offset in `from`/`to`,
    /// so passing local-time offsets makes "today" match the user's calendar day.
    /// Pass `login` to show someone else's graph; nil means the account that owns the token.
    func fetchSnapshot(login: String? = nil, now: Date = .now) async throws -> ContributionSnapshot {
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))!
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current

        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ContribBar", forHTTPHeaderField: "User-Agent")
        var variables = ["from": iso.string(from: from), "to": iso.string(from: now)]
        if let login { variables["login"] = login }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": login == nil
                ? Self.query(root: "viewer", declaresLogin: false)
                : Self.query(root: "user(login: $login)", declaresLogin: true),
            "variables": variables,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw ClientError.unauthorized }
        guard (200..<300).contains(status) else { throw ClientError.http(status) }

        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        if let error = decoded.errors?.first {
            if error.type == "NOT_FOUND", let login { throw ClientError.userNotFound(login) }
            throw ClientError.api(error.message)
        }
        guard let account = decoded.data?.account else {
            if let login { throw ClientError.userNotFound(login) }
            throw ClientError.noData
        }

        let cal = account.contributionsCollection.contributionCalendar
        return ContributionSnapshot(
            login: account.login,
            totalContributions: cal.totalContributions,
            weeks: cal.weeks,
            fetchedAt: now
        )
    }
}

private struct GraphQLResponse: Decodable {
    struct Payload: Decodable { let account: Account? }
    struct Account: Decodable {
        let login: String
        let contributionsCollection: Collection
    }
    struct Collection: Decodable { let contributionCalendar: CalendarData }
    struct CalendarData: Decodable {
        let totalContributions: Int
        let weeks: [ContributionWeek]
    }
    struct GraphQLError: Decodable {
        let message: String
        let type: String?
    }

    let data: Payload?
    let errors: [GraphQLError]?
}
