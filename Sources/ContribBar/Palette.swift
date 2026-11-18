import AppKit
import SwiftUI

/// GitHub's contribution greens, with separate light and dark ramps.
enum Palette {
    static func color(_ level: ContributionLevel) -> Color {
        Color(nsColor: nsColor(level))
    }

    static func nsColor(_ level: ContributionLevel) -> NSColor {
        let (light, dark): (UInt32, UInt32) = switch level {
        case .none: (0xEBEDF0, 0x2D333B)
        case .first: (0x9BE9A8, 0x0E4429)
        case .second: (0x40C463, 0x006D32)
        case .third: (0x30A14E, 0x26A641)
        case .fourth: (0x216E39, 0x39D353)
        }
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum MenuBarIcon {
    /// A row of tiny squares, one per day — drawn lazily so colors match the menu bar's appearance.
    static func image(for days: [ContributionDay]) -> NSImage {
        let cell: CGFloat = 6, gap: CGFloat = 1.5
        let count = max(days.count, 1)
        let size = NSSize(width: CGFloat(count) * cell + CGFloat(count - 1) * gap, height: cell)
        let levels = days.map(\.contributionLevel)
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, level) in levels.enumerated() {
                let rect = NSRect(x: CGFloat(index) * (cell + gap), y: 0, width: cell, height: cell)
                let fill = level == .none
                    ? NSColor.secondaryLabelColor.withAlphaComponent(0.35)
                    : Palette.nsColor(level)
                fill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
