import Foundation
import Observation
import UIKit

/// Copies of everything the app keeps, in a folder the user picks once (iCloud Drive included):
/// the library with its words and statistics, the notes, the study marks, the bookmarks, the
/// AI concepts and the settings. Each backup is a dated folder; the last few are kept.
/// A free signing (SideStore) cannot use iCloud sync, so the copy goes through the Files app.
@MainActor
@Observable
final class BackupService {
    static let shared = BackupService()

    enum State: Equatable {
        case idle
        case running
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var lastBackup: Date?
    /// Name of the chosen folder, to show it.
    private(set) var folderName: String?
    var isAutomatic: Bool {
        didSet { UserDefaults.standard.set(isAutomatic, forKey: Self.automaticKey) }
    }

    /// How many backups stay in the folder; older ones are removed.
    nonisolated static let kept = 5
    private static let bookmarkKey = "backup.folderBookmark"
    private static let lastKey = "backup.last"
    private static let automaticKey = "backup.automatic"
    nonisolated private static let prefix = "PencilReader "
    nonisolated private static let settingsFile = "impostazioni.plist"
    /// Under Application Support: notes, study marks, bookmarks, AI concepts.
    nonisolated private static let supportFolders = ["Notes", "Annotations", "Bookmarks", "HighlightGroups"]

    private init() {
        let defaults = UserDefaults.standard
        isAutomatic = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        lastBackup = defaults.object(forKey: Self.lastKey) as? Date
        folderName = (try? resolvedFolder()).map(Self.name(of:))
    }

    var hasFolder: Bool { folderName != nil }

    /// Remembers the folder picked in the Files app.
    func choose(_ folder: URL) throws {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        folderName = Self.name(of: folder)
    }

    /// "Su iPad" rather than the folder's name on disk.
    private static func name(of folder: URL) -> String {
        (try? folder.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? folder.lastPathComponent
    }

    /// Once a day, when the app leaves the screen, if automatic backups are on.
    func backUpIfDue() {
        guard isAutomatic, hasFolder, state != .running else { return }
        if let lastBackup, Date.now.timeIntervalSince(lastBackup) < 20 * 3600 { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "backup")
        Task {
            await backUp()
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    func backUp() async {
        guard state != .running else { return }
        state = .running
        do {
            let folder = try resolvedFolder()
            let name = Self.prefix + Self.stamp.string(from: .now)
            try await Task.detached(priority: .utility) {
                try Self.write(into: folder, name: name)
            }.value
            lastBackup = .now
            UserDefaults.standard.set(lastBackup, forKey: Self.lastKey)
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Puts a backup back in place of everything the app has now. The app must be reopened after it.
    func restore(from backup: URL) async throws {
        state = .running
        defer { if state == .running { state = .idle } }
        try await Task.detached(priority: .userInitiated) {
            try Self.read(backup)
        }.value
    }

    /// Whether a folder picked to restore is a backup made here.
    nonisolated static func isBackup(_ folder: URL) -> Bool {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: folder.appending(path: "Libreria").path)
    }

    // MARK: Files

    private func resolvedFolder() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { throw BackupError.noFolder }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey) }
        return url
    }

    private static var stamp: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }

    nonisolated private static func write(into folder: URL, name: String) throws {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        // Built aside, then moved in one step: a backup cut short never looks complete.
        let staging = manager.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        let library = URL.documentsDirectory.appending(path: "Libreria")
        if manager.fileExists(atPath: library.path) {
            try manager.copyItem(at: library, to: staging.appending(path: "Libreria"))
        }
        for sub in supportFolders {
            let source = URL.applicationSupportDirectory.appending(path: sub)
            guard manager.fileExists(atPath: source.path) else { continue }
            try manager.copyItem(at: source, to: staging.appending(path: sub))
        }
        try settingsData().write(to: staging.appending(path: settingsFile))

        var coordinationError: NSError?
        var moveError: Error?
        let destination = folder.appending(path: name, directoryHint: .isDirectory)
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing,
                                       error: &coordinationError) { target in
            do {
                try? manager.removeItem(at: target)
                try manager.copyItem(at: staging, to: target)
            } catch {
                moveError = error
            }
        }
        try? manager.removeItem(at: staging)
        if let error = coordinationError ?? moveError { throw error }
        try prune(folder)
    }

    /// Keeps the newest `kept` backups.
    nonisolated private static func prune(_ folder: URL) throws {
        let manager = FileManager.default
        let backups = try manager.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(prefix) }
            .sorted(by: >)
        for old in backups.dropFirst(kept) {
            try? manager.removeItem(at: folder.appending(path: old))
        }
    }

    nonisolated private static func read(_ backup: URL) throws {
        let access = backup.startAccessingSecurityScopedResource()
        defer { if access { backup.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        // Downloads the iCloud copy first, if it is only in the cloud.
        var coordinationError: NSError?
        var copyError: Error?
        let staging = manager.temporaryDirectory.appending(path: "ripristino", directoryHint: .isDirectory)
        try? manager.removeItem(at: staging)
        NSFileCoordinator().coordinate(readingItemAt: backup, options: [], error: &coordinationError) { source in
            do { try manager.copyItem(at: source, to: staging) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        defer { try? manager.removeItem(at: staging) }

        let pairs = [("Libreria", URL.documentsDirectory.appending(path: "Libreria"))]
            + supportFolders.map { ($0, URL.applicationSupportDirectory.appending(path: $0)) }
        for (name, target) in pairs {
            let source = staging.appending(path: name)
            guard manager.fileExists(atPath: source.path) else { continue }
            try? manager.removeItem(at: target)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: target)
        }
        if let data = try? Data(contentsOf: staging.appending(path: settingsFile)),
           let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in settings where !key.hasPrefix("backup.") {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    /// The app's own settings; the system's keys and the backup's own state stay out.
    nonisolated private static func settingsData() throws -> Data {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let own = domain.filter { key, _ in
            !key.hasPrefix("backup.") && !key.hasPrefix("Apple") && !key.hasPrefix("NS") && !key.hasPrefix("com.apple")
        }
        return try PropertyListSerialization.data(fromPropertyList: own, format: .binary, options: 0)
    }
}

enum BackupError: LocalizedError {
    case noFolder

    var errorDescription: String? {
        switch self {
        case .noFolder: String(localized: "Scegli prima la cartella dei backup.")
        }
    }
}
