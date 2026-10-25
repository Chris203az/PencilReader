import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var library
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(open: { path = [$0.id] })
                .navigationDestination(for: UUID.self) { id in
                    if let document = library.document(withID: id) {
                        ReaderView(document: document)
                    }
                }
        }
    }
}
