import SwiftUI

/// How the page image is shown while reading. Only the view changes: OCR, thumbnails
/// and the files on disk always use the original page.
enum ReadingTheme: String, CaseIterable, Identifiable {
    case normal
    case sepia
    case night
    /// Night when the iPad is in dark mode, normal otherwise.
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "Normale"
        case .sepia: "Seppia"
        case .night: "Notte"
        case .system: "Segui il sistema"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "sun.max"
        case .sepia: "book"
        case .night: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }

    /// The theme actually drawn: `system` becomes normal or night.
    func resolved(for scheme: ColorScheme) -> ReadingTheme {
        guard self == .system else { return self }
        return scheme == .dark ? .night : .normal
    }

    // MARK: Saved per book

    /// Also the theme of books never set, chosen in Impostazioni.
    static let lastKey = "readingTheme"
    private static func key(for bookID: UUID) -> String { "readingTheme.\(bookID.uuidString)" }

    /// The book's theme; a book never set takes the last one chosen.
    static func saved(for bookID: UUID) -> ReadingTheme {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: key(for: bookID)) ?? defaults.string(forKey: lastKey)
        return raw.flatMap(ReadingTheme.init(rawValue:)) ?? .normal
    }

    static func save(_ theme: ReadingTheme, for bookID: UUID) {
        UserDefaults.standard.set(theme.rawValue, forKey: key(for: bookID))
        UserDefaults.standard.set(theme.rawValue, forKey: lastKey)
    }
}

extension View {
    /// Tints a page image for the theme. Night inverts it and turns the hues back
    /// (hue + 180°), so a red figure stays red and only light and dark swap;
    /// the white is a soft gray, not pure white on black.
    @ViewBuilder func readingTheme(_ theme: ReadingTheme) -> some View {
        switch theme {
        case .normal, .system:
            self
        case .sepia:
            self.colorMultiply(Color(red: 0.98, green: 0.91, blue: 0.77))
        case .night:
            self.colorInvert()
                .hueRotation(.degrees(180))
                .colorMultiply(Color(white: 0.86))
        }
    }
}

extension ReadingTheme {
    /// Around the page.
    var background: Color {
        switch self {
        case .normal, .system: Color(.secondarySystemBackground)
        case .sepia: Color(red: 0.93, green: 0.88, blue: 0.78)
        case .night: Color(white: 0.06)
        }
    }
}
