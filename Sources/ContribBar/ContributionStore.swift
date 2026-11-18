import AppKit
import SwiftUI

/// Where the current data came from — shown in Settings so it's clear what's being used.
enum DataSource: Equatable {
    case api(TokenSource)  // GraphQL API with a token
    case publicProfile  // github.com public graph, no token
}

@MainActor
final class ContributionStore: ObservableObject {
    static let usernameKey = "githubUsername"

    @Published private(set) var snapshot: ContributionSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var tokenSource: TokenSource?
    @Published private(set) var dataSource: DataSource?
    @Published private(set) var username: String?

    private static let refreshInterval: Duration = .seconds(10 * 60)
    private var loop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init() {
        username = UserDefaults.standard.string(forKey: Self.usernameKey)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refreshIfStale(olderThan seconds: TimeInterval = 60) async {
        guard let fetched = snapshot?.fetchedAt,
              Date.now.timeIntervalSince(fetched) < seconds
        else { return await refresh() }
    }

    /// Source order: a token (Keychain, then `gh`) uses the official API — for `username` if set,
    /// otherwise the token's own account. With no token, a username falls back to the public profile graph.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let resolved = await Task.detached(priority: .userInitiated) { TokenStore.resolve() }.value
        tokenSource = resolved?.source

        do {
            if let resolved {
                snapshot = try await GitHubClient(token: resolved.token).fetchSnapshot(login: username)
                dataSource = .api(resolved.source)
            } else if let username {
                snapshot = try await PublicContributions.fetchSnapshot(login: username)
                dataSource = .publicProfile
            } else {
                dataSource = nil
                errorMessage = "Add your GitHub username in Settings to get started."
                return
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// GitHub usernames: 1–39 letters, digits or single hyphens, not starting or ending with a hyphen.
    static func isValidUsername(_ name: String) -> Bool {
        name.wholeMatch(of: #/[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}/#) != nil
    }

    /// Pass nil or an empty string to clear it and go back to the token's own account.
    func setUsername(_ name: String?) async {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard value != username else { return }
        username = value
        UserDefaults.standard.set(value, forKey: Self.usernameKey)
        snapshot = nil  // don't keep showing the previous account's graph
        await refresh()
    }

    func saveToken(_ token: String) async throws {
        try TokenStore.save(token)
        await refresh()
    }

    func clearToken() async {
        TokenStore.clear()
        await refresh()
    }
}
