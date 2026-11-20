import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ContributionStore
    let done: () -> Void

    @AppStorage(Appearance.transparencyKey) private var transparency = Appearance.defaultTransparency
    @AppStorage(Appearance.themeKey) private var theme: Theme = .system
    @State private var usernameDraft = ""
    @State private var token = ""
    @State private var fieldError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("Username").gridColumnAlignment(.trailing)
                            TextField("e.g. octocat", text: $usernameDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(saveUsername)
                            Button("Save", action: saveUsername)
                                .buttonStyle(.glass)
                                .disabled(!usernameChanged)
                        }
                        GridRow {
                            Text("Token")
                            SecureField("Optional — ghp_… or github_pat_…", text: $token)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(saveToken)
                            HStack(spacing: 6) {
                                Button("Save", action: saveToken)
                                    .buttonStyle(.glass)
                                    .disabled(trimmedToken.isEmpty)
                                if store.tokenSource == .keychain {
                                    Button("Remove") { Task { await store.clearToken() } }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fieldError {
                        Text(fieldError).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(6)
            } label: {
                Text("GitHub").font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Picker("Theme", selection: $theme) {
                            ForEach(Theme.glass) { Text($0.title).tag($0) }
                            Divider()
                            ForEach(Theme.finishes) { theme in
                                if let finish = theme.finish {
                                    Label { Text(theme.title) } icon: { Image(nsImage: finish.swatch) }
                                        .tag(theme)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                    HStack {
                        Text("Transparency")
                        Spacer()
                        Text(theme.finish != nil ? "Solid finish" : transparency.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $transparency, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Solid").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Clear").font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(theme.finish != nil)  // a solid finish has no glass to see through
                }
                .padding(6)
            } label: {
                Text("Appearance").font(.headline)
            }

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = enabled
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                ))
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { usernameDraft = store.username ?? "" }
    }

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var trimmedUsername: String {
        usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private var usernameChanged: Bool { trimmedUsername != (store.username ?? "") }

    private var statusDescription: String {
        let who = store.username.map { "@\($0)" }
        switch store.dataSource {
        case .api(let source):
            let via = source == .ghCLI ? "your GitHub CLI login" : "your saved token"
            if let who { return "Showing \(who) via the GitHub API, using \(via)." }
            return "Showing the account of \(via). Enter a username to show a different profile."
        case .publicFallback:
            return "GitHub's API isn't responding right now, so this is \(who.map { "\($0)'s" } ?? "your") public graph for the moment. "
                + "ContribBar will switch back to the API automatically on the next refresh."
        case .publicProfile:
            return "Showing \(who ?? "this user")'s public graph — no token needed. Private contributions appear only "
                + "if enabled on the profile, and days may not follow your timezone. Add a token for the official API."
        case nil:
            return "Enter your GitHub username — no token needed. Or run `gh auth login` / paste a token to use the official API."
        }
    }

    private func saveUsername() {
        let name = trimmedUsername
        guard name.isEmpty || ContributionStore.isValidUsername(name) else {
            fieldError = "“\(name)” isn't a valid GitHub username."
            return
        }
        fieldError = nil
        Task { await store.setUsername(name) }
    }

    private func saveToken() {
        let value = trimmedToken
        guard !value.isEmpty else { return }
        Task {
            do {
                try await store.saveToken(value)
                token = ""
                fieldError = nil
            } catch {
                fieldError = "Couldn't save to Keychain: \(error.localizedDescription)"
            }
        }
    }
}
