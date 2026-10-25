#if DEBUG
import UIKit

/// Diagnostics: each time the on-screen keyboard is about to appear, writes down which object
/// asked for it and its responder chain, in Documents/diagnostica-tastiera.txt.
/// Debug builds only; it reads and changes nothing else.
@MainActor
enum KeyboardProbe {
    private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { record() }
        }
    }

    private static func record() {
        var chain: [String] = []
        var responder = UIResponder.probedFirstResponder
        while let current = responder, chain.count < 12 {
            chain.append(String(describing: type(of: current)))
            responder = current.next
        }
        let first = UIResponder.probedFirstResponder
        let line = "\(Date().formatted(date: .omitted, time: .standard)) tastiera per: \(chain.joined(separator: " → "))"
            + " | inputView: \(first?.inputView.map { String(describing: type(of: $0)) } ?? "nessuna")"
            + " | UIKeyInput: \(first is UIKeyInput)\n"
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostica-tastiera.txt") else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// Diagnostics of the notebook's Pencil strokes, in Documents/diagnostica-quaderno.txt. Debug builds only.
enum NotebookDiagnostics {
    static func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostica-quaderno.txt") else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?

    /// The first responder, found by sending an action to whichever object is first.
    static var probedFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(markAsFound), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func markAsFound() {
        UIResponder.found = self
    }
}
#endif
