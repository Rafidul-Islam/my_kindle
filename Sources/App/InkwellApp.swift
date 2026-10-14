import SwiftUI

@main
struct InkwellApp: App {

    @State private var store = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store)
                .environment(store)
                .onOpenURL { url in
                    handleIncoming(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.saveNow()
            }
        }
    }

    /// Handles "Open in Inkwell…" from Files, Mail or Safari.
    private func handleIncoming(_ url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        Task { @MainActor in
            do {
                let book = try await ImportService.shared.importBook(from: url)
                store.upsert(book)
                store.saveNow()
            } catch {
                // Nothing to show here: a failed "open in" is silent by design.
            }
        }
    }
}