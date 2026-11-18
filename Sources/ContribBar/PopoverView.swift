import AppKit
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"
    case year = "Year"

    var id: Self { self }
}

enum Appearance {
    static let transparencyKey = "transparency"
    static let defaultTransparency = 0.4
    static let themeKey = "theme"  // must match `UserDefaults.theme` below, which is observed via KVO
    static let cornerRadius: CGFloat = 22
}

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// nil means "inherit the system appearance".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension UserDefaults {
    /// KVO-observable mirror of `Appearance.themeKey` (the property name must equal the key).
    @objc dynamic var theme: String {
        string(forKey: Appearance.themeKey) ?? Theme.system.rawValue
    }
}

struct PopoverView: View {
    static let width: CGFloat = 640
    static let padding: CGFloat = 18
    static var contentWidth: CGFloat { width - padding * 2 }
    /// Tab picker + tallest tab (the charts, ~230pt) — also fits Settings (~287pt).
    static let bodyHeight: CGFloat = 290

    @EnvironmentObject private var store: ContributionStore
    @AppStorage("selectedTab") private var tab: Tab = .today
    @AppStorage(Appearance.transparencyKey) private var transparency = Appearance.defaultTransparency
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            // Fixed height: the panel never resizes. (Animated window resizes behind Liquid Glass
            // crashed inside the system's glass renderer, and a steady panel feels calmer anyway.)
            Group {
                if showingSettings {
                    ScrollView {
                        SettingsView { showingSettings = false }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("View", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .frame(height: Self.bodyHeight, alignment: .top)
            Divider()
            footer
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        // Transparency = how much of the solid backing sits on top of the clear glass.
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(1 - transparency),
            in: .rect(cornerRadius: Appearance.cornerRadius)
        )
        .glassEffect(.clear, in: .rect(cornerRadius: Appearance.cornerRadius))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.snapshot.map { "@\($0.login)" } ?? "GitHub Contributions")
                    .font(.headline)
                if let snapshot = store.snapshot {
                    Text("\(snapshot.totalContributions.formatted()) contributions in the last year")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: store.isLoading)
            }
            .help("Refresh")
            .disabled(store.isLoading)
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
            }
            .help(showingSettings ? "Close settings" : "Settings")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = store.snapshot {
            switch tab {
            case .today: TodayView(snapshot: snapshot)
            case .week: RangeView(days: snapshot.last(7), kind: .week)
            case .month: RangeView(days: snapshot.last(30), kind: .month)
            case .year: YearView(snapshot: snapshot, width: Self.contentWidth)
            }
        } else if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(store.errorMessage ?? "No data yet.")
                    .multilineTextAlignment(.center)
                Button("Open Settings") { showingSettings = true }
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Group {
                if let error = store.errorMessage, store.snapshot != nil {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(error)
                } else if store.isLoading {
                    Text("Refreshing…")
                } else if let snapshot = store.snapshot {
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer()

            if let login = store.snapshot?.login,
               let url = URL(string: "https://github.com/\(login)") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("GitHub Profile", systemImage: "arrow.up.right")
                }
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.glass)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.color(.third))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension Int {
    var contributionsLabel: String { self == 1 ? "1 contribution" : "\(formatted()) contributions" }
}
