import SwiftUI
import AppKit

/// Shared visual language for the menu bar, workspace, and focus surfaces.
enum SeedoStyle {
    static let accent = adaptive(light: 0x216B59, dark: 0x8ED9BB)
    static let canvas = adaptive(light: 0xF4F5F1, dark: 0x131A19)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C2523)
    static let ink = Color.primary
    static let night = Color(red: 0.045, green: 0.075, blue: 0.065)
    static let mint = Color(red: 0.56, green: 0.85, blue: 0.73)
    static let line = Color.primary.opacity(0.09)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func color(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255,
                    blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

struct SeedoButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .foregroundStyle(prominent ? (scheme == .dark ? SeedoStyle.night : .white) : .primary)
            .background(prominent ? SeedoStyle.accent : Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(prominent ? Color.clear : SeedoStyle.line))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension View {
    func seedoCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(SeedoStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SeedoStyle.line))
    }

    func seedoInput() -> some View {
        self.padding(11)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SeedoStyle.line))
    }
}

struct SeedoPageHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SeedoStyle.accent)
                .frame(width: 44, height: 44)
                .background(SeedoStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct SeedoCategoryPicker: View {
    let categories: [SessionCategory]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(categories) { category in
                Button { selection = category.id } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selection == category.id ? "checkmark.circle.fill" : "circle.fill")
                            .font(.system(size: selection == category.id ? 12 : 6))
                            .foregroundStyle(category.color)
                        Text(category.name).font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selection == category.id ? category.color.opacity(0.14) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selection == category.id ? category.color.opacity(0.6) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == category.id ? .isSelected : [])
            }
        }
    }
}
