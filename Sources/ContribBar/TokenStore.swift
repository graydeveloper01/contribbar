import Foundation
import Security

enum TokenSource: Sendable {
    case keychain
    case ghCLI
}

struct ResolvedToken: Sendable {
    let token: String
    let source: TokenSource
}

/// A token saved in the Keychain wins; otherwise fall back to the GitHub CLI's login.
enum TokenStore {
    private static let service = "local.contribbar"
    private static let account = "github-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Blocking (may spawn `gh`) — call off the main thread.
    static func resolve() -> ResolvedToken? {
        if let token = saved() { return ResolvedToken(token: token, source: .keychain) }
        if let token = ghCLIToken() { return ResolvedToken(token: token, source: .ghCLI) }
        return nil
    }

    static func saved() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        clear()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// GUI apps don't inherit the shell PATH, so look in the usual install locations.
    static func ghCLIToken() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["auth", "token"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
